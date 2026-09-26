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
        string(from: oldInfo.remote_info),
        newCallID,
        string(from: newInfo.remote_info)
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
        string(from: $0.pointee)
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
