//
//  PJSUACallbacks.swift
//  Telephone
//
//  Swift implementations of the small PJSIP C callbacks.
//

import Foundation
import PJSIPBridge

@c @implementation
func PJSUAOnAccountRegistrationState(_ accountID: pjsua_acc_id) {
    Task { @MainActor in
        guard let account = AKSIPUserAgent.shared().account(
            withIdentifier: Int(accountID)
        ) else {
            return
        }

        account.delegate?.sipAccountRegistrationDidChange(account)
    }
}

@c @implementation
func PJSUAOnCallReplaced(
    _ oldCallID: pjsua_call_id,
    _ newCallID: pjsua_call_id
) {
    var oldInfo = pjsua_call_info()
    var newInfo = pjsua_call_info()

    guard
        pjsua_call_get_info(oldCallID, &oldInfo) == 0,
        pjsua_call_get_info(newCallID, &newInfo) == 0
    else {
        return
    }

    Log.sip.info(
        """
        Replacing call old=\(oldCallID, privacy: .public) \
        oldRemote=\(pjStringValue(oldInfo.remote_info), privacy: .private) \
        new=\(newCallID, privacy: .public) \
        newRemote=\(pjStringValue(newInfo.remote_info), privacy: .private)
        """
    )

    let snapshot = PJSUACallInfo(
        info: newInfo,
        parser: AKSIPUserAgent.shared().parser
    )

    Task { @MainActor in
        guard let account = AKSIPUserAgent.shared().account(
            withIdentifier: snapshot.accountIdentifier
        ) else {
            return
        }

        _ = account.addCall(info: snapshot)
    }
}

@c @implementation
func PJSUAOnCallTransferStatus(
    _ callID: pjsua_call_id,
    _ statusCode: CInt,
    _ statusText: UnsafePointer<pj_str_t>?,
    _ isFinal: pj_bool_t,
    _ wantsFurtherNotifications: UnsafeMutablePointer<pj_bool_t>?
) {
    let statusText = statusText.map {
        pjStringValue($0.pointee)
    } ?? ""
    let isFinal = isFinal != 0

    Log.sip.info(
        """
        Transfer status call=\(callID, privacy: .public) \
        status=\(statusCode, privacy: .public) \
        final=\(isFinal, privacy: .public) \
        text=\(statusText, privacy: .private)
        """
    )

    if statusCode / 100 == 2 {
        _ = pjsua_call_hangup(
            callID,
            410,
            nil,
            nil
        )
        wantsFurtherNotifications?.pointee = 0
    }

    Task { @MainActor in
        guard let call = AKSIPUserAgent.shared().call(
            withIdentifier: Int(callID)
        ) else {
            return
        }

        call.transferStatus = Int(statusCode)
        call.transferStatusText = statusText

        publishCallEvent(
            .AKSIPCallTransferStatusDidChange,
            call: call,
            userInfo: [
                "AKFinalTransferNotification": isFinal,
            ]
        )
    }
}

@c @implementation
func PJSUAOnNATDetect(
    _ result: UnsafePointer<pj_stun_nat_detect_result>?
) {
    guard let result else {
        return
    }

    let detection = result.pointee
    guard detection.status == 0 else {
        Log.sip.error(
            "NAT detection failed status=\(detection.status, privacy: .public)"
        )
        return
    }

    let natType = detection.nat_type

    Task { @MainActor in
        let agent = AKSIPUserAgent.shared()
        agent.detectedNATType = natType

        let notification = Notification(
            name: .AKSIPUserAgentDidDetectNAT,
            object: agent
        )
        NotificationCenter.default.post(notification)
        agent.delegate?.sipUserAgentDidDetectNAT(notification)
    }
}

//
// MARK: - Incoming calls

@c @implementation
func PJSUAOnIncomingCall(
    _ accountID: pjsua_acc_id,
    _ callID: pjsua_call_id,
    _ invite: UnsafeMutablePointer<pjsip_rx_data>?
) {
    var info = pjsua_call_info()
    guard pjsua_call_get_info(callID, &info) == 0 else {
        return
    }

    let agent = AKSIPUserAgent.shared()
    let snapshot = PJSUACallInfo(
        info: info,
        parser: agent.parser
    )
    let headers = incomingIdentityHeaders(from: invite)

    if headers.isEmpty {
        Log.sip.debug("Incoming identity headers: none")
    } else {
        Log.sip.debug(
            "Incoming identity headers captured count=\(headers.count, privacy: .public)"
        )
    }

    SIPCallEventSequence.shared.enqueueCall(
        identifier: Int(callID), account: agent.captureAccount(withIdentifier: Int(accountID)), incoming: true
    ) { incarnation in
        guard let account = incarnation.account as? AKSIPAccount else { return }
        let call = account.addCall(info: snapshot, incarnation: incarnation)
        guard account.identifier >= 0 else {
            call.duration = incarnation.latestDuration.withLock { $0 } ?? 0
            agent.finalizeCall(call)
            return
        }
        call.incomingIdentityHeaders = headers
        account.delegate?.sipAccount(account, didReceive: call)

        publishCallEvent(.AKSIPCallIncoming, call: call)
    }
}

private let incomingIdentityHeaderNames = [
    "P-Asserted-Identity",
    "P-Preferred-Identity",
    "Remote-Party-ID",
    "Diversion",
    "History-Info",
    "X-Caller-ID",
    "X-Caller-Name",
    "X-Customer-ID",
    "X-Company",
]

private func incomingIdentityHeaders(
    from invite: UnsafeMutablePointer<pjsip_rx_data>?
) -> [String: String] {
    var result: [String: String] = [:]

    for name in incomingIdentityHeaderNames {
        if let value = incomingHeaderValue(
            from: invite,
            name: name
        ), !value.isEmpty {
            result[name] = value
        }
    }

    return result
}

private func incomingHeaderValue(
    from invite: UnsafeMutablePointer<pjsip_rx_data>?,
    name: String
) -> String? {
    guard let message = invite?.pointee.msg_info.msg else {
        return nil
    }

    return withPJString(name) { headerName in
        guard let header = pjsip_msg_find_hdr_by_name(
            message,
            &headerName,
            nil
        ) else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: 2_048)
        let length = buffer.withUnsafeMutableBufferPointer {
            pjsip_hdr_print_on(
                header,
                $0.baseAddress,
                $0.count - 1
            )
        }

        guard
            length > 0,
            length < buffer.count
        else {
            return nil
        }

        let bytes = buffer.prefix(Int(length)).map {
            UInt8(bitPattern: $0)
        }
        let line = String(decoding: bytes, as: UTF8.self)

        let value: Substring
        if let colon = line.firstIndex(of: ":") {
            value = line[line.index(after: colon)...]
        } else {
            value = Substring(line)
        }

        return value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }
}


// MARK: - Call state

@c @implementation
func PJSUAOnCallState(
    _ callID: pjsua_call_id,
    _ event: UnsafeMutablePointer<pjsip_event>?
) {
    var info = pjsua_call_info()
    guard pjsua_call_get_info(callID, &info) == 0 else {
        return
    }

    let agent = AKSIPUserAgent.shared()
    let snapshot = PJSUACallInfo(
        info: info,
        parser: agent.parser
    )
    let duration = Int(info.connect_duration.sec)

    let provisionalCode =
        snapshot.state == PJSIP_INV_STATE_EARLY
            ? snapshot.lastStatus
            : nil
    let provisionalReason =
        provisionalCode == nil
            ? nil
            : snapshot.lastStatusText

    let firstMedia: pjsua_call_media_info? =
        Array(tuple: info.media).first
    let shouldStartRingback =
        snapshot.state == PJSIP_INV_STATE_EARLY
        && info.role.rawValue == PJSIP_ROLE_UAC.rawValue
        && snapshot.lastStatus == 180
        && firstMedia?.status.rawValue
            == PJSUA_CALL_MEDIA_NONE.rawValue

    SIPCallEventSequence.shared.enqueueCall(
        identifier: Int(callID),
        account: agent.captureAccount(withIdentifier: snapshot.accountIdentifier),
        startsCall: snapshot.state == PJSIP_INV_STATE_CALLING,
        endsCall: snapshot.state == PJSIP_INV_STATE_DISCONNECTED,
        duration: duration
    ) { incarnation in
        guard let account = incarnation.account as? AKSIPAccount else { return }
        var call = incarnation.call.withLock { $0 as? AKSIPCall }

        if call == nil, snapshot.state == PJSIP_INV_STATE_CALLING {
            call = account.addCall(info: snapshot, incarnation: incarnation)
        }

        guard let call else {
            Log.sip.error(
                "Could not find call during state change call=\(callID, privacy: .public)"
            )
            return
        }

        guard !call.hasPublishedDisconnect else { return }
        call.duration = duration
        guard account.identifier >= 0 else {
            agent.finalizeCall(call)
            return
        }
        call.state = snapshot.state
        call.stateText = snapshot.stateText
        call.lastStatus = snapshot.lastStatus
        call.lastStatusText = snapshot.lastStatusText
        call.duration = duration

        switch snapshot.state {
        case PJSIP_INV_STATE_DISCONNECTED:
            agent.finalizeCall(call)

        case PJSIP_INV_STATE_EARLY:
            if shouldStartRingback {
                agent.startRingback(for: call)
            }

            var userInfo: [AnyHashable: Any]?
            if let provisionalCode, let provisionalReason {
                userInfo = [
                    "AKSIPEventCode": provisionalCode,
                    "AKSIPEventReason": provisionalReason,
                ]
            }

            publishCallEvent(
                .AKSIPCallEarly,
                call: call,
                userInfo: userInfo
            )

        case PJSIP_INV_STATE_CALLING:
            publishCallEvent(.AKSIPCallCalling, call: call)

        case PJSIP_INV_STATE_CONNECTING:
            publishCallEvent(.AKSIPCallConnecting, call: call)

        case PJSIP_INV_STATE_CONFIRMED:
            publishCallEvent(.AKSIPCallDidConfirm, call: call)

        default:
            break
        }
    }
}


// MARK: - Media state

@c @implementation
func PJSUAOnCallMediaState(_ callID: pjsua_call_id) {
    var info = pjsua_call_info()
    guard pjsua_call_get_info(callID, &info) == 0 else {
        Log.sip.error(
            "Could not get media info call=\(callID, privacy: .public)"
        )
        return
    }

    let media: [pjsua_call_media_info] = Array(tuple: info.media)
    let activeMedia = media.prefix(Int(info.media_cnt))

    guard let audio = activeMedia.first(where: {
        $0.type.rawValue == PJMEDIA_TYPE_AUDIO.rawValue
    }) else {
        Log.audio.error(
            "Call has no audio media call=\(callID, privacy: .public)"
        )
        return
    }

    let statusRawValue = audio.status.rawValue
    let conferencePort = audio.stream.aud.conf_slot

    let agent = AKSIPUserAgent.shared()
    SIPCallEventSequence.shared.enqueueCall(
        identifier: Int(callID), account: agent.captureAccount(withIdentifier: Int(info.acc_id))
    ) { incarnation in
        guard agent.isStarted,
              let call = incarnation.call.withLock({ $0 as? AKSIPCall }),
              !call.hasPublishedDisconnect,
              call.sipAccount.identifier >= 0 else { return }

        if statusRawValue == PJSUA_CALL_MEDIA_ACTIVE.rawValue
            || statusRawValue
                == PJSUA_CALL_MEDIA_REMOTE_HOLD.rawValue
        {
            _ = pjsua_conf_connect(conferencePort, 0)
            if !call.isMicrophoneMuted {
                _ = pjsua_conf_connect(0, conferencePort)
            }
        }

        agent.stopRingback(for: call)

        let name: Notification.Name?
        switch statusRawValue {
        case PJSUA_CALL_MEDIA_ACTIVE.rawValue:
            name = .AKSIPCallMediaDidBecomeActive
        case PJSUA_CALL_MEDIA_LOCAL_HOLD.rawValue:
            name = .AKSIPCallDidLocalHold
        case PJSUA_CALL_MEDIA_REMOTE_HOLD.rawValue:
            name = .AKSIPCallDidRemoteHold
        default:
            name = nil
        }

        if let name {
            publishCallEvent(name, call: call)
        }
    }
}


// MARK: - Incoming account matching

@c @implementation
func PJSUAOnAccountFindForIncoming(
    _ data: UnsafePointer<pjsip_rx_data>?,
    _ accountID: UnsafeMutablePointer<pjsua_acc_id>?
) {
    guard
        let accountID,
        let toURI = TelephonePJSIPIncomingToURI(data),
        let requestURI = TelephonePJSIPIncomingRequestURI(data)
    else {
        return
    }

    let capacity = Int(PJSUA_MAX_ACC)
    let accounts = UnsafeMutablePointer<pjsua_acc_info>.allocate(
        capacity: capacity
    )
    defer { accounts.deallocate() }

    var count = UInt32(capacity)
    guard pjsua_acc_enum_info(accounts, &count) == 0 else {
        return
    }

    let toUser = pjStringValue(toURI.pointee.user)
    let toHost = pjStringValue(toURI.pointee.host)
    let requestUser = pjStringValue(requestURI.pointee.user)
    let requestHost = pjStringValue(requestURI.pointee.host)

    var bestScore = 0
    var bestIdentifier = pjsua_acc_id(-1)

    for index in 0..<Int(count) {
        let info = accounts[index]
        guard info.id >= 0 else {
            continue
        }

        guard let uri = AKSIPURI(
            string: pjStringValue(info.acc_uri)
        ) else {
            continue
        }

        var score = 0

        if equalsIgnoringCase(uri.host, toHost) {
            score += 10
        }
        if equalsIgnoringCase(uri.host, requestHost) {
            score += 10
        }
        if equalsIgnoringCase(uri.user, toUser) {
            score += 1
        }
        if equalsIgnoringCase(uri.user, requestUser) {
            score += 1
        }

        if score > bestScore {
            bestScore = score
            bestIdentifier = info.id
        }
    }

    if bestIdentifier >= 0 {
        accountID.pointee = bestIdentifier
    }
}

private func equalsIgnoringCase(
    _ lhs: String,
    _ rhs: String
) -> Bool {
    lhs.caseInsensitiveCompare(rhs) == .orderedSame
}


@MainActor
func publishCallEvent(
    _ name: Notification.Name,
    call: AKSIPCall,
    userInfo: [AnyHashable: Any]? = nil
) {
    let notification = Notification(
        name: name,
        object: call,
        userInfo: userInfo
    )

    NotificationCenter.default.post(notification)

    guard let delegate = call.delegate else {
        return
    }

    switch name {
    case .AKSIPCallCalling:
        delegate.sipCallCalling(notification)
    case .AKSIPCallIncoming:
        delegate.sipCallIncoming(notification)
    case .AKSIPCallEarly:
        delegate.sipCallEarly(notification)
    case .AKSIPCallConnecting:
        delegate.sipCallConnecting(notification)
    case .AKSIPCallDidConfirm:
        delegate.sipCallDidConfirm(notification)
    case .AKSIPCallDidDisconnect:
        delegate.sipCallDidDisconnect(notification)
    case .AKSIPCallMediaDidBecomeActive:
        delegate.sipCallMediaDidBecomeActive(notification)
    case .AKSIPCallDidLocalHold:
        delegate.sipCallDidLocalHold(notification)
    case .AKSIPCallDidRemoteHold:
        delegate.sipCallDidRemoteHold(notification)
    case .AKSIPCallTransferStatusDidChange:
        delegate.sipCallTransferStatusDidChange(notification)
    default:
        break
    }
}
