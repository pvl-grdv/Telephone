//
//  SIPRuntimeTypes.swift
//  Telephone
//
//  Swift-facing types at the PJSIP boundary.
//

import Foundation

typealias AKSIPCallState = pjsip_inv_state
typealias AKNATType = pj_stun_nat_type

enum AKSIPUserAgentState: Int {
    case stopped
    case starting
    case started
    case stopping
}

let kAKSIPUserAgentInvalidIdentifier = Int(PJSUA_INVALID_ID)

@MainActor
protocol AKSIPCallDelegate: AnyObject {
    func sipCallCalling(_ notification: Notification)
    func sipCallIncoming(_ notification: Notification)
    func sipCallEarly(_ notification: Notification)
    func sipCallConnecting(_ notification: Notification)
    func sipCallDidConfirm(_ notification: Notification)
    func sipCallDidDisconnect(_ notification: Notification)
    func sipCallMediaDidBecomeActive(_ notification: Notification)
    func sipCallDidLocalHold(_ notification: Notification)
    func sipCallDidRemoteHold(_ notification: Notification)
    func sipCallTransferStatusDidChange(_ notification: Notification)
}

extension AKSIPCallDelegate {
    func sipCallCalling(_ notification: Notification) {}
    func sipCallIncoming(_ notification: Notification) {}
    func sipCallEarly(_ notification: Notification) {}
    func sipCallConnecting(_ notification: Notification) {}
    func sipCallDidConfirm(_ notification: Notification) {}
    func sipCallDidDisconnect(_ notification: Notification) {}
    func sipCallMediaDidBecomeActive(_ notification: Notification) {}
    func sipCallDidLocalHold(_ notification: Notification) {}
    func sipCallDidRemoteHold(_ notification: Notification) {}
    func sipCallTransferStatusDidChange(_ notification: Notification) {}
}

@MainActor
protocol AKSIPAccountDelegate: AnyObject {
    func sipAccountRegistrationDidChange(_ account: AKSIPAccount)
    func sipAccountWillRemove(_ account: AKSIPAccount)
    func sipAccount(_ account: AKSIPAccount, didReceive call: AKSIPCall)
}

@MainActor
protocol AKSIPUserAgentDelegate: AnyObject {
    func sipUserAgentShouldAdd(_ account: AKSIPAccount) -> Bool
    func sipUserAgentDidFinishStarting(_ notification: Notification)
    func sipUserAgentDidFinishStopping(_ notification: Notification)
    func sipUserAgentDidDetectNAT(_ notification: Notification)
}

extension AKSIPUserAgentDelegate {
    func sipUserAgentShouldAdd(_ account: AKSIPAccount) -> Bool { true }
    func sipUserAgentDidFinishStarting(_ notification: Notification) {}
    func sipUserAgentDidFinishStopping(_ notification: Notification) {}
    func sipUserAgentDidDetectNAT(_ notification: Notification) {}
}
