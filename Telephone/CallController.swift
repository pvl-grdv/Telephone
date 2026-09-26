//
//  CallController.swift
//  Telephone
//
//  Coordinates one SIP call with its SwiftUI presentation.
//

import AppKit
import Foundation
import UserNotifications

@MainActor
@objc(CallController)
@objcMembers
class CallController: NSObject, @preconcurrency AKSIPCallDelegate {
    private static let autoCloseDelay: TimeInterval = 1.5
    private static let redialEnableDelay: TimeInterval = 1.0

    weak var delegate: (any CallControllerDelegate)?
    weak var accountController: AccountController?

    let identifier = UUID().uuidString

    var call: AKSIPCall? {
        didSet {
            guard oldValue !== call else { return }

            if oldValue?.delegate === self {
                oldValue?.delegate = nil
            }

            call?.delegate = self
            presentation.setCall(call)

            guard let call else { return }

            presentation.setWindowDismissEnabled(true)
            presentation.setHangUpEnabled(true)
            populateRemoteIdentityIfNeeded(from: call)
        }
    }

    private var transferController: CallTransferController?

    var callTransferController: CallTransferController? {
        if transferController == nil {
            transferController = CallTransferController(
                sourceCallController: self,
                userAgent: userAgent
            )
        }
        return transferController
    }

    var title: String? {
        didSet {
            guard oldValue != title else { return }
            presentation.setWindowTitle(title ?? "")
        }
    }

    var displayedName: String? {
        didSet {
            guard oldValue != displayedName else { return }
            presentation.setDisplayedName(displayedName ?? "")
        }
    }

    var identityDetail: String? {
        didSet {
            guard oldValue != identityDetail else { return }
            presentation.setIdentityDetail(identityDetail ?? "")
        }
    }

    var organizationFromAddressBook: String? {
        didSet {
            guard oldValue != organizationFromAddressBook else { return }
            presentation.setContactOrganization(
                organizationFromAddressBook ?? ""
            )
        }
    }

    var status: String? {
        didSet {
            guard oldValue != status else { return }
            presentation.setStatus(status ?? "")
        }
    }

    var nameFromAddressBook: String?
    var phoneLabelFromAddressBook: String?
    var enteredCallDestination: String?
    var redialURI: AKSIPURI?
    var callStartTime: TimeInterval = 0

    @objc(isCallOnHold)
    var callOnHold = false

    @objc(isCallActive)
    var callActive = false

    @objc(isCallUnhandled)
    var callUnhandled: Bool {
        call?.isMissed ?? false
    }

    let userAgent: AKSIPUserAgent
    let defaults: UserDefaults
    private(set) var presentation: CallPresentationCoordinator!

    private var didHandleWindowClose = false

    @objc(initWithWindowNibName:accountController:userAgent:delegate:)
    init(
        windowNibName: String,
        accountController: AccountController,
        userAgent: AKSIPUserAgent,
        delegate: (any CallControllerDelegate)?
    ) {
        let isTransfer = windowNibName == "CallTransfer"
        precondition(
            windowNibName == "Call" || isTransfer,
            "Unsupported call window: \(windowNibName)"
        )

        self.accountController = accountController
        self.userAgent = userAgent
        self.delegate = delegate
        defaults = .standard

        super.init()

        presentation = CallPresentationCoordinator(
            callController: self,
            accountController: accountController,
            isTransfer: isTransfer
        )

        if isTransfer {
            title = NSLocalizedString(
                "Call Transfer",
                comment: "Call transfer window title."
            )
        }
    }

    isolated deinit {
        presentation.invalidate()
        if call?.delegate === self {
            call?.delegate = nil
        }
    }

    override var description: String {
        call?.description ?? super.description
    }

    @objc(showWindow:)
    func showWindow(_ sender: Any?) {
        didHandleWindowClose = false
        presentation.showWindow()
    }

    func close() {
        presentation.closeWindow()
        callWindowDidClose()
    }

    func callWindowDidClose() {
        guard !didHandleWindowClose else { return }
        didHandleWindowClose = true

        if callActive {
            callActive = false
            presentation.stopCallTimer()

            if call?.delegate === self {
                call?.delegate = nil
            }

            call?.hangUp()
        }

        delegate?.callControllerWillClose(self)
    }

    @objc(setShowsAccountInfo:)
    func setShowsAccountInfo(_ visible: Bool) {
        presentation.setShowsAccountInfo(visible)
    }

    func discardCallTransfer() {
        guard let transferController else { return }

        self.transferController = nil
        transferController.close()
    }

    func acceptCall() {
        call?.answer()
        removeUserNotification()
    }

    func hangUpCall() {
        callActive = false
        presentation.stopCallTimer()

        if call?.delegate === self {
            call?.delegate = nil
        }

        call?.hangUp()

        status = NSLocalizedString("call ended", comment: "Call ended.")
        showEndedCallView()

        presentation.setProgressVisible(false)
        presentation.setHangUpEnabled(false)
        presentation.setIncomingActionsEnabled(false)

        removeUserNotification()

        if defaults.bool(forKey: UserDefaultsKeys.autoCloseCallWindow),
           !(self is CallTransferController)
        {
            presentation.scheduleAutoClose(
                after: Self.autoCloseDelay
            )
        }
    }

    func redial() {
        guard
            userAgent.isStarted,
            accountController?.enabled == true,
            accountController?.canMakeCalls == true,
            let redialURI
        else {
            return
        }

        presentation.cancelAutoClose()

        if accountController?.substitutesPlusCharacter == true,
           redialURI.user.hasPrefix("+")
        {
            let replacement =
                accountController?.plusCharacterSubstitution ?? ""
            redialURI.user =
                replacement + redialURI.user.dropFirst()
        }

        prepareForCall()

        if let phoneLabelFromAddressBook,
           !phoneLabelFromAddressBook.isEmpty
        {
            status = String(
                format: NSLocalizedString(
                    "calling %@...",
                    comment: "Outgoing call in progress."
                ),
                phoneLabelFromAddressBook
            )
        } else {
            status = NSLocalizedString(
                "calling...",
                comment: "Outgoing call in progress."
            )
        }

        accountController?.account.makeCall(
            to: redialURI
        ) { [weak self] call in
            Task { @MainActor in
                guard let self else { return }

                if let call {
                    self.call = call
                    self.callActive = true
                } else {
                    self.showEndedCallView()
                    self.status = NSLocalizedString(
                        "Call Failed",
                        comment: "Call failed."
                    )
                }
            }
        }
    }

    @objc(setCallHeld:)
    func setCallHeld(_ held: Bool) {
        guard
            call?.state.rawValue == 5,
            call?.isOnRemoteHold == false
        else {
            return
        }

        call?.setHeld(held)
    }

    func toggleCallHold() {
        setCallHeld(!(call?.isOnLocalHold ?? false))
    }

    @objc(setMicrophoneMuted:)
    func setMicrophoneMuted(_ muted: Bool) {
        guard call?.state.rawValue == 5 else {
            return
        }

        call?.setMuted(muted)

        if call?.isMicrophoneMuted == true {
            if !callOnHold {
                presentation.stopCallTimer()
                status = NSLocalizedString(
                    "mic muted",
                    comment: "Microphone muted status text."
                )
            } else {
                setIntermediateStatus(
                    NSLocalizedString(
                        "mic muted",
                        comment: "Microphone muted status text."
                    )
                )
            }
        } else {
            setIntermediateStatus(
                NSLocalizedString(
                    "mic unmuted",
                    comment: "Microphone unmuted status text."
                )
            )
        }
    }

    func toggleMicrophoneMute() {
        setMicrophoneMuted(!(call?.isMicrophoneMuted ?? false))
    }

    @objc(setIntermediateStatus:)
    func setIntermediateStatus(_ newStatus: String) {
        presentation.showIntermediateStatus(newStatus)
    }

    func prepareForCall() {
        presentation.setWindowDismissEnabled(false)
        showActiveCallView()
        presentation.setProgressVisible(true)
        presentation.setHangUpEnabled(false)
    }

    func showActiveCallView() {
        if !(self is CallTransferController) {
            title = NSLocalizedString(
                "Call Window Title",
                comment: "Active call window title."
            )
        }

        presentation.showActiveState()
    }

    func showEndedCallView() {
        if !(self is CallTransferController) {
            title = NSLocalizedString(
                "Call Ended",
                comment: "Ended call window title."
            )
        }

        presentation.setWindowDismissEnabled(true)
        presentation.showEndedState()
    }

    func showIncomingCallView() {
        title = NSLocalizedString(
            "Incoming Call",
            comment: "Incoming call window title."
        )
        presentation.showIncomingState()
    }

    // MARK: - Transfer presentation hooks

    func showTransferDestinationState() {
        presentation.showTransferDestinationState()
    }

    func focusTransferDestination() {
        presentation.focusTransferDestination()
    }

    func setTransferActionEnabled(_ enabled: Bool) {
        presentation.setTransferActionEnabled(enabled)
    }

    func callDidHoldForTransfer() {
        presentation.callDidHoldForTransfer()
    }

    func dismissCallTransfer() {
        presentation.dismissTransfer()
    }

    // MARK: - AKSIPCallDelegate

    @objc(SIPCallEarly:)
    func sipCallEarly(_ notification: Notification) {
        guard call?.isIncoming == false else { return }

        let code = notification.userInfo?["AKSIPEventCode"] as? NSNumber
        if code?.intValue == 180 {
            presentation.setProgressVisible(false)
            status = NSLocalizedString(
                "ringing",
                comment: "Remote party ringing."
            )
        }
    }

    @objc(SIPCallDidConfirm:)
    func sipCallDidConfirm(_ notification: Notification) {
        removeUserNotification()
        callStartTime = Date.timeIntervalSinceReferenceDate
        showActiveCallView()
        presentation.setProgressVisible(false)
        presentation.updateCallControls()
        status = "00:00"
        presentation.startCallTimer()
    }

    @objc(SIPCallDidDisconnect:)
    func sipCallDidDisconnect(_ notification: Notification) {
        callActive = false
        presentation.stopCallTimer()

        status = disconnectedStatus()

        showEndedCallView()
        presentation.setRedialEnabled(false)
        presentation.setProgressVisible(false)
        presentation.setHangUpEnabled(false)
        presentation.setIncomingActionsEnabled(false)
        presentation.scheduleRedialEnable(
            after: Self.redialEnableDelay
        )

        removeOrShowUserNotificationOnDisconnectIfNeeded()

        if defaults.bool(forKey: UserDefaultsKeys.autoCloseCallWindow),
           !(self is CallTransferController)
        {
            presentation.scheduleAutoClose(
                after: Self.autoCloseDelay
            )
        }
    }

    @objc(SIPCallMediaDidBecomeActive:)
    func sipCallMediaDidBecomeActive(_ notification: Notification) {
        presentation.updateCallControls()

        if callOnHold {
            callOnHold = false
            setIntermediateStatus(
                NSLocalizedString(
                    "off hold",
                    comment: "Call has been taken off hold status text."
                )
            )
        }
    }

    @objc(SIPCallDidLocalHold:)
    func sipCallDidLocalHold(_ notification: Notification) {
        callOnHold = true
        presentation.updateCallControls()
        presentation.stopCallTimer()
        status = NSLocalizedString(
            "on hold",
            comment: "Call on local hold status text."
        )
    }

    @objc(SIPCallDidRemoteHold:)
    func sipCallDidRemoteHold(_ notification: Notification) {
        callOnHold = true
        presentation.updateCallControls()
        presentation.stopCallTimer()
        status = NSLocalizedString(
            "on remote hold",
            comment: "Call on remote hold status text."
        )
    }

    @objc(SIPCallTransferStatusDidChange:)
    func sipCallTransferStatusDidChange(_ notification: Notification) {
        let final =
            notification.userInfo?["AKFinalTransferNotification"] as? Bool
                ?? false

        if final, call?.transferStatus == 200 {
            hangUpCall()
            status = NSLocalizedString(
                "call transferred",
                comment: "Call transferred."
            )
        }
    }

    // MARK: - Identity and notifications

    private func populateRemoteIdentityIfNeeded(from call: AKSIPCall) {
        let formatter = AKSIPURIFormatter()
        formatter.formatsTelephoneNumbers =
            defaults.bool(forKey: UserDefaultsKeys.formatTelephoneNumbers)
        formatter.telephoneNumberFormatterSplitsLastFourDigits =
            defaults.bool(
                forKey:
                    UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits
            )

        let remoteIdentity = formatter.string(for: call.remoteURI)
        let remoteAddress = call.remoteURI.sipAddress.isEmpty
            ? remoteIdentity
            : call.remoteURI.sipAddress

        if title?.isEmpty != false {
            title = remoteAddress
        }

        if displayedName?.isEmpty != false {
            displayedName = remoteIdentity ?? remoteAddress
        }
    }

    private func disconnectedStatus() -> String {
        guard let call else { return "" }

        switch call.lastStatus {
        case 200, 487:
            return NSLocalizedString("call ended", comment: "Call ended.")
        case 404:
            return NSLocalizedString(
                "Address Not Found",
                comment: "Address not found."
            )
        case 486, 600:
            return NSLocalizedString("busy", comment: "Busy.")
        case 603:
            return NSLocalizedString(
                "call declined",
                comment: "Call declined."
            )
        default:
            if Bundle.main.preferredLocalizations.first == "ru" {
                return SIPResponseLocalization.localizedString(
                    for: call.lastStatus
                ) ?? String(
                    format: NSLocalizedString(
                        "Error %ld",
                        comment: "Error #."
                    ),
                    call.lastStatus
                )
            }

            return call.lastStatusText
        }
    }

    private func removeOrShowUserNotificationOnDisconnectIfNeeded() {
        guard !NSApp.isActive else { return }

        if callUnhandled {
            removeUserNotification()
        } else {
            showUserNotification()
        }
    }

    private func removeUserNotification() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(
            withIdentifiers: [identifier]
        )
        center.removePendingNotificationRequests(
            withIdentifiers: [identifier]
        )
    }

    private func showUserNotification() {
        let content = UNMutableNotificationContent()
        content.title = notificationTitle()
        content.body = status ?? ""

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog(
                    "Could not deliver call notification: %@",
                    error.localizedDescription
                )
            }
        }
    }

    private func notificationTitle() -> String {
        if let nameFromAddressBook, !nameFromAddressBook.isEmpty {
            return nameFromAddressBook
        }

        if let enteredCallDestination, !enteredCallDestination.isEmpty {
            guard
                defaults.bool(
                    forKey: UserDefaultsKeys.formatTelephoneNumbers
                ),
                isTelephoneNumber(enteredCallDestination)
            else {
                return enteredCallDestination
            }

            return AKTelephoneNumberFormatter().string(
                for: enteredCallDestination
            ) ?? enteredCallDestination
        }

        let formatter = AKSIPURIFormatter()
        formatter.formatsTelephoneNumbers =
            defaults.bool(forKey: UserDefaultsKeys.formatTelephoneNumbers)
        formatter.telephoneNumberFormatterSplitsLastFourDigits =
            defaults.bool(
                forKey:
                    UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits
            )

        return call.flatMap { formatter.string(for: $0.remoteURI) } ?? ""
    }
}

private func isTelephoneNumber(_ value: String) -> Bool {
    let digits = value.first == "+"
        ? value.dropFirst()
        : Substring(value)

    return !digits.isEmpty
        && digits.allSatisfy { $0 >= "0" && $0 <= "9" }
}
