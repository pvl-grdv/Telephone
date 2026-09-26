//
//  NotificationNames.swift
//  Telephone
//
//  Strongly typed names for the legacy Objective-C notifications.
//

import Foundation

extension Notification.Name {
    static let AKSIPCallCalling =
        Notification.Name("AKSIPCallCalling")
    static let AKSIPCallIncoming =
        Notification.Name("AKSIPCallIncoming")
    static let AKSIPCallEarly =
        Notification.Name("AKSIPCallEarly")
    static let AKSIPCallConnecting =
        Notification.Name("AKSIPCallConnecting")
    static let AKSIPCallDidConfirm =
        Notification.Name("AKSIPCallDidConfirm")
    static let AKSIPCallDidDisconnect =
        Notification.Name("AKSIPCallDidDisconnect")
    static let AKSIPCallMediaDidBecomeActive =
        Notification.Name("AKSIPCallMediaDidBecomeActive")
    static let AKSIPCallDidLocalHold =
        Notification.Name("AKSIPCallDidLocalHold")
    static let AKSIPCallDidRemoteHold =
        Notification.Name("AKSIPCallDidRemoteHold")
    static let AKSIPCallTransferStatusDidChange =
        Notification.Name("AKSIPCallTransferStatusDidChange")

    static let AKSIPUserAgentDidFinishStarting =
        Notification.Name("AKSIPUserAgentDidFinishStarting")
    static let AKSIPUserAgentDidFinishStopping =
        Notification.Name("AKSIPUserAgentDidFinishStopping")
    static let AKSIPUserAgentDidDetectNAT =
        Notification.Name("AKSIPUserAgentDidDetectNAT")

    static let AKPreferencesControllerDidRemoveAccount =
        Notification.Name("AKPreferencesControllerDidRemoveAccount")
    static let AKPreferencesControllerDidChangeAccountEnabled =
        Notification.Name("AKPreferencesControllerDidChangeAccountEnabled")
    static let AKPreferencesControllerDidSwapAccounts =
        Notification.Name("AKPreferencesControllerDidSwapAccounts")
    static let AKPreferencesControllerDidChangeNetworkSettings =
        Notification.Name("AKPreferencesControllerDidChangeNetworkSettings")
}


enum PreferencesNotificationKey {
    static let accountIndex = "AccountIndex"
    static let sourceIndex = "SourceIndex"
    static let destinationIndex = "DestinationIndex"
}
