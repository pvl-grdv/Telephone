//
//  PJSUACallbacks.swift
//  Telephone
//
//  Swift implementations of the small PJSIP C callbacks.
//

import Foundation

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

    NSLog(
        "Call %d with %@ is being replaced by call %d with %@",
        oldCallID,
        pjStringValue(oldInfo.remote_info),
        newCallID,
        pjStringValue(newInfo.remote_info)
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

    NSLog(
        "Call %d transfer status=%d (%@)%@",
        callID,
        statusCode,
        statusText,
        isFinal ? " [final]" : ""
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

        NotificationCenter.default.post(
            name: .AKSIPCallTransferStatusDidChange,
            object: call,
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
        NSLog("NAT detection failed with status %d", detection.status)
        return
    }

    let natType = AKNATType(
        rawValue: UInt(detection.nat_type.rawValue)
    ) ?? AKNATType(rawValue: 0)!

    Task { @MainActor in
        let agent = AKSIPUserAgent.shared()
        agent.detectedNATType = natType

        NotificationCenter.default.post(
            name: .AKSIPUserAgentDidDetectNAT,
            object: agent
        )
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
        NSLog("Incoming identity headers: none")
    } else {
        NSLog(
            "Incoming identity headers captured: %ld",
            headers.count
        )
    }

    Task { @MainActor in
        guard let account = agent.account(
            withIdentifier: Int(accountID)
        ) else {
            return
        }

        let call = account.addCall(info: snapshot)
        call.incomingIdentityHeaders = headers
        account.delegate?.sipAccount(account, didReceive: call)

        NotificationCenter.default.post(
            name: .AKSIPCallIncoming,
            object: call
        )
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

        buffer[Int(length)] = 0
        let line = String(cString: buffer)

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
        snapshot.state.rawValue == 3
            ? snapshot.lastStatus
            : nil
    let provisionalReason =
        provisionalCode == nil
            ? nil
            : snapshot.lastStatusText

    let firstMedia: pjsua_call_media_info? =
        Array(tuple: info.media).first
    let shouldStartRingback =
        snapshot.state.rawValue == 3
        && info.role.rawValue == PJSIP_ROLE_UAC.rawValue
        && snapshot.lastStatus == 180
        && firstMedia?.status.rawValue
            == PJSUA_CALL_MEDIA_NONE.rawValue

    Task { @MainActor in
        var call = agent.call(
            withIdentifier: Int(callID)
        )

        if call == nil, snapshot.state.rawValue == 1 {
            guard let account = agent.account(
                withIdentifier: snapshot.accountIdentifier
            ) else {
                NSLog(
                    "Could not find account for call %d",
                    callID
                )
                return
            }
            call = account.addCall(info: snapshot)
        }

        guard let call else {
            NSLog(
                "Could not find call %d during state change",
                callID
            )
            return
        }

        call.state = snapshot.state
        call.stateText = snapshot.stateText
        call.lastStatus = snapshot.lastStatus
        call.lastStatusText = snapshot.lastStatusText
        call.duration = duration

        let center = NotificationCenter.default

        switch snapshot.state.rawValue {
        case 6:
            agent.stopRingback(for: call)
            call.account.remove(call)
            center.post(
                name: .AKSIPCallDidDisconnect,
                object: call
            )

        case 3:
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

            center.post(
                name: .AKSIPCallEarly,
                object: call,
                userInfo: userInfo
            )

        case 1:
            center.post(
                name: .AKSIPCallCalling,
                object: call
            )

        case 4:
            center.post(
                name: .AKSIPCallConnecting,
                object: call
            )

        case 5:
            center.post(
                name: .AKSIPCallDidConfirm,
                object: call
            )

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
        NSLog("Could not get media info for call %d", callID)
        return
    }

    let media: [pjsua_call_media_info] = Array(tuple: info.media)
    let activeMedia = media.prefix(Int(info.media_cnt))

    guard let audio = activeMedia.first(where: {
        $0.type.rawValue == PJMEDIA_TYPE_AUDIO.rawValue
    }) else {
        NSLog("Call %d has no audio media", callID)
        return
    }

    let status = audio.status
    let conferencePort = audio.stream.aud.conf_slot

    Task { @MainActor in
        let agent = AKSIPUserAgent.shared()
        guard let call = agent.call(
            withIdentifier: Int(callID)
        ) else {
            return
        }

        if status.rawValue == PJSUA_CALL_MEDIA_ACTIVE.rawValue
            || status.rawValue
                == PJSUA_CALL_MEDIA_REMOTE_HOLD.rawValue
        {
            _ = pjsua_conf_connect(conferencePort, 0)
            if !call.isMicrophoneMuted {
                _ = pjsua_conf_connect(0, conferencePort)
            }
        }

        agent.stopRingback(for: call)

        let name: Notification.Name?
        switch status.rawValue {
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
            NotificationCenter.default.post(
                name: name,
                object: call
            )
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
