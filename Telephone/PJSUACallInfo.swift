//
//  PJSUACallInfo.swift
//  Telephone
//
//  Safe snapshot of the PJSIP call information used by the app.
//

import Foundation
import PJSIPBridge

struct PJSUACallInfo: Sendable {
    let identifier: Int
    let accountIdentifier: Int
    private let stateRawValue: AKSIPCallState.RawValue
    let stateText: String
    let lastStatus: Int
    let lastStatusText: String
    let localURI: SIPURISnapshot
    let remoteURI: SIPURISnapshot
    let isIncoming: Bool

    var state: AKSIPCallState {
        AKSIPCallState(rawValue: stateRawValue)
    }

    init(
        info: pjsua_call_info,
        parser: AKSIPURIParser
    ) {
        identifier = Int(info.id)
        accountIdentifier = Int(info.acc_id)
        stateRawValue = info.state.rawValue
        stateText = pjStringValue(info.state_text)
        lastStatus = Int(info.last_status.rawValue)
        lastStatusText = pjStringValue(info.last_status_text)
        localURI = SIPURISnapshot(
            parser.sipURI(from: pjStringValue(info.local_info))
        )
        remoteURI = SIPURISnapshot(
            parser.sipURI(from: pjStringValue(info.remote_info))
        )
        isIncoming = info.role == PJSIP_ROLE_UAS
    }
}


