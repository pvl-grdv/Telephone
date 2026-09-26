//
//  PJSUACallInfo.swift
//  Telephone
//
//  Safe snapshot of the PJSIP call information used by the app.
//

import Foundation

public final class PJSUACallInfo: @unchecked Sendable {
    public let identifier: Int
    public let accountIdentifier: Int
    public let state: AKSIPCallState
    public let stateText: String
    public let lastStatus: Int
    public let lastStatusText: String
    public let localURI: AKSIPURI
    public let remoteURI: AKSIPURI
    private final let incomingValue: Bool

    public var isIncoming: Bool {
        incomingValue
    }

    public init(
        info: pjsua_call_info,
        parser: AKSIPURIParser
    ) {
        identifier = Int(info.id)
        accountIdentifier = Int(info.acc_id)
        state = info.state
        stateText = swiftString(info.state_text)
        lastStatus = Int(info.last_status.rawValue)
        lastStatusText = swiftString(info.last_status_text)
        localURI = parser.sipURI(from: swiftString(info.local_info))
            ?? AKSIPURI()
        remoteURI = parser.sipURI(from: swiftString(info.remote_info))
            ?? AKSIPURI()
        incomingValue = info.role == PJSIP_ROLE_UAS
    }
}

private func swiftString(_ value: pj_str_t) -> String {
    guard let pointer = value.ptr, value.slen > 0 else {
        return ""
    }

    return String(
        bytesNoCopy: UnsafeMutableRawPointer(pointer),
        length: Int(value.slen),
        encoding: .utf8,
        freeWhenDone: false
    ) ?? ""
}

