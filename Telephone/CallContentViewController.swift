//
//  CallContentViewController.swift
//  Telephone
//

import AppKit
import Observation
import SwiftUI

@MainActor
@objcMembers
final class CallContentViewController: NSViewController, NSMenuItemValidation {
    private weak var callController: CallController?
    private weak var accountController: AccountController?
    private let model: CallWindowModel
    private let transferDestinationController: ActiveAccountTransferViewController?

    private var accountInfoObservation: NSKeyValueObservation?
    private var callTimer: Foundation.Timer?
    private var enteredDTMF = NSMutableString()
    private var waitingForTransferHold = false

    private var customerContextSaveTask: Task<Void, Never>?
    private var loadedCustomerContextKey: String?
    private var isApplyingCustomerContext = false

    @objc(initWithCallController:accountController:isTransfer:)
    init(
        callController: CallController,
        accountController: AccountController,
        isTransfer: Bool
    ) {
        self.callController = callController
        self.accountController = accountController

        let model = CallWindowModel(isTransfer: isTransfer)
        model.accountDescription = accountController.accountDescription
        model.showsAccountInfo =
            !isTransfer && accountController.callsShouldDisplayAccountInfo
        self.model = model

        transferDestinationController = isTransfer
            ? ActiveAccountTransferViewController(accountController: accountController)
            : nil

        super.init(nibName: nil, bundle: nil)

        guard !isTransfer else { return }

        accountInfoObservation = accountController.observe(
            \.callsShouldDisplayAccountInfo,
            options: [.initial, .new]
        ) { [weak self] _, change in
            Task { @MainActor [weak self] in
                self?.model.showsAccountInfo = change.newValue ?? false
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = CallWindowView(
            model: model,
            transferDestinationController: transferDestinationController,
            answer: { [weak self] in self?.acceptCall(nil) },
            decline: { [weak self] in self?.hangUpCall(nil) },
            hangUp: { [weak self] in self?.hangUpCall(nil) },
            toggleMute: { [weak self] in self?.toggleMicrophoneMute(nil) },
            toggleHold: { [weak self] in self?.toggleCallHold(nil) },
            showTransfer: { [weak self] in self?.showCallTransferSheet(nil) },
            redial: { [weak self] in self?.redial(nil) },
            cancelTransfer: { [weak self] in self?.cancelTransfer() },
            completeTransfer: { [weak self] in self?.completeTransfer() },
            customerContextChanged: { [weak self] in
                self?.scheduleCustomerContextSave()
            }
        )

        let hostingView = DTMFCapturingHostingView(rootView: rootView)
        hostingView.onText = { [weak self] text in
            self?.handleDTMF(text)
        }
        view = hostingView
    }

    override func viewWillDisappear() {
        saveCustomerContextNow()
        super.viewWillDisappear()
    }

    func setCall(_ call: AKSIPCall?) {
        waitingForTransferHold = false
        enteredDTMF = NSMutableString()
        model.usesDTMFDisplay = false
        updateCallControls()

        if call != nil {
            loadCustomerContextIfNeeded()
        }
    }

    func setDisplayedName(_ value: String) {
        model.displayedName = value
    }

    func setStatus(_ value: String) {
        model.status = value
    }

    func showIncomingState() {
        guard !model.isTransfer else { return }
        model.phase = .incoming
        model.incomingActionsEnabled = true
        model.showsProgress = false
        loadCustomerContextIfNeeded()
        focusAnswer()
    }

    func showActiveState() {
        model.phase = model.isTransfer ? .transferActive : .active
        updateCallControls()
        loadCustomerContextIfNeeded()
        focusCallSurface()
    }

    func showEndedState() {
        model.phase = model.isTransfer ? .transferEnded : .ended
        model.showsProgress = false
        stopCallTimer()
        loadCustomerContextIfNeeded()
    }

    func showTransferDestinationState() {
        guard model.isTransfer else { return }
        waitingForTransferHold = false
        model.phase = .transferDestination
        model.transferActionEnabled = false
        transferDestinationController?.focusCallDestination()
    }

    func setProgressVisible(_ visible: Bool) {
        model.showsProgress = visible
        updateCallControls()
    }

    func setHangUpEnabled(_ enabled: Bool) {
        model.hangUpEnabled = enabled
        if model.isTransfer {
            model.transferCancelEnabled = enabled
        }
    }

    func setIncomingActionsEnabled(_ enabled: Bool) {
        model.incomingActionsEnabled = enabled
    }

    func setRedialEnabled(_ enabled: Bool) {
        model.redialEnabled = enabled
    }

    func setTransferActionEnabled(_ enabled: Bool) {
        model.transferActionEnabled = enabled
    }

    func setTransferCancelEnabled(_ enabled: Bool) {
        model.transferCancelEnabled = enabled
    }

    func focusAnswer() {
        model.answerFocusRequest &+= 1
    }

    func focusTransferDestination() {
        transferDestinationController?.focusCallDestination()
    }

    func updateCallControls() {
        guard let call = callController?.call else {
            model.muteEnabled = false
            model.holdEnabled = false
            model.transferEnabled = false
            return
        }

        let confirmed = call.isConfirmed
        model.muted = call.isMicrophoneMuted
        model.muteEnabled = confirmed
        model.held = call.isOnLocalHold
        model.holdEnabled = confirmed && !call.isOnRemoteHold
        model.transferEnabled =
            !model.isTransfer && confirmed && !call.isOnRemoteHold
    }

    func startCallTimer() {
        guard callTimer?.isValid != true else { return }

        callTimer = Foundation.Timer.scheduledTimer(
            withTimeInterval: 0.2,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCallDuration()
            }
        }
    }

    func stopCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
    }

    private func updateCallDuration() {
        guard let callController else { return }

        let seconds = Int(
            Date.timeIntervalSinceReferenceDate - callController.callStartTime
        )
        let value: String

        if seconds < 3600 {
            value = String(
                format: "%02d:%02d",
                (seconds / 60) % 60,
                seconds % 60
            )
        } else {
            value = String(
                format: "%02d:%02d:%02d",
                (seconds / 3600) % 24,
                (seconds / 60) % 60,
                seconds % 60
            )
        }

        callController.status = value
    }

    @objc func enableRedialButtonTick(_ timer: Foundation.Timer) {
        model.redialEnabled = true
    }

    func callDidHoldForTransfer() {
        guard
            waitingForTransferHold,
            let transferController = callController as? CallTransferController
        else {
            return
        }

        transferController.transferCall()
        waitingForTransferHold = false
    }

    @IBAction func acceptCall(_ sender: Any?) {
        callController?.acceptCall()
    }

    @IBAction func hangUpCall(_ sender: Any?) {
        callController?.hangUpCall()
    }

    @IBAction func toggleCallHold(_ sender: Any?) {
        guard let call = callController?.call else { return }
        callController?.setCallHeld(!call.isOnLocalHold)
        updateCallControls()
    }

    @IBAction func toggleMicrophoneMute(_ sender: Any?) {
        guard let call = callController?.call else { return }
        callController?.setMicrophoneMuted(!call.isMicrophoneMuted)
        updateCallControls()
    }

    @IBAction func showCallTransferSheet(_ sender: Any?) {
        guard
            !model.isTransfer,
            let callController
        else {
            return
        }

        if !callController.isCallOnHold {
            callController.setCallHeld(true)
        }

        guard
            let transferWindow = callController.callTransferController?.window,
            let parentWindow = callController.window
        else {
            return
        }

        parentWindow.beginSheet(transferWindow)
    }

    @IBAction func redial(_ sender: Any?) {
        callController?.redial()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleMicrophoneMute(_:)):
            menuItem.title = model.muted
                ? NSLocalizedString("Unmute", comment: "Unmute. Call menu item.")
                : NSLocalizedString("Mute", comment: "Mute. Call menu item.")
            return model.phase == .active && model.muteEnabled

        case #selector(toggleCallHold(_:)):
            menuItem.title = model.held
                ? NSLocalizedString("Resume", comment: "Resume. Call menu item.")
                : NSLocalizedString("Hold", comment: "Hold. Call menu item.")
            return (model.phase == .active || model.phase == .transferActive)
                && model.holdEnabled

        case #selector(showCallTransferSheet(_:)):
            return model.phase == .active && model.transferEnabled

        case #selector(acceptCall(_:)):
            return model.phase == .incoming && model.incomingActionsEnabled

        case #selector(hangUpCall(_:)):
            menuItem.title = model.phase == .incoming
                ? NSLocalizedString("Decline", comment: "Decline. Call menu item.")
                : NSLocalizedString("End Call", comment: "End Call. Call menu item.")
            switch model.phase {
            case .incoming:
                return model.incomingActionsEnabled
            case .active, .transferActive:
                return model.hangUpEnabled
            default:
                return false
            }

        case #selector(redial(_:)):
            return (model.phase == .ended || model.phase == .transferEnded)
                && model.redialEnabled

        default:
            return true
        }
    }

    private func completeTransfer() {
        guard
            let callController,
            let transferController = callController as? CallTransferController
        else {
            return
        }

        if callController.isCallOnHold {
            transferController.transferCall()
        } else {
            callController.toggleCallHold()
            model.transferActionEnabled = false
            waitingForTransferHold = true
        }
    }

    private func cancelTransfer() {
        guard
            let transferController = callController as? CallTransferController
        else {
            return
        }

        transferController.showInitialState(nil)
    }

    private func focusCallSurface() {
        guard model.phase == .active || model.phase == .transferActive else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self, self.view.window != nil else { return }
            self.view.window?.makeFirstResponder(self.view)
        }
    }

    private func handleDTMF(_ text: String) {
        guard
            model.phase == .active || model.phase == .transferActive,
            let callController,
            let call = callController.call
        else {
            return
        }

        let allowed = CharacterSet(charactersIn: "0123456789*#abcdrABCDR")
        guard text.unicodeScalars.allSatisfy(allowed.contains) else { return }

        if enteredDTMF.length == 0 {
            view.window?.title = callController.displayedName
            model.usesDTMFDisplay = true
        }

        enteredDTMF.append(text)
        callController.displayedName = enteredDTMF as String
        call.sendDTMFDigits(text)
    }

    private var customerPartyAddress: CustomerPartyAddress? {
        guard !model.isTransfer, let callController else { return nil }

        if let uri = callController.call?.remoteURI ?? callController.redialURI {
            return CustomerPartyAddress(user: uri.user, host: uri.host)
        }

        let entered = callController.enteredCallDestination?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !entered.isEmpty else { return nil }
        return CustomerPartyAddress(user: entered, host: "")
    }

    private var customerDisplayName: String {
        guard let callController else { return "" }

        let addressBookName = callController.nameFromAddressBook ?? ""
        if !addressBookName.isEmpty {
            return addressBookName
        }

        return callController.displayedName ?? ""
    }

    private func loadCustomerContextIfNeeded() {
        guard
            !model.isTransfer,
            let callController,
            let address = customerPartyAddress,
            let callIdentifier = callController.identifier,
            !callIdentifier.isEmpty
        else {
            return
        }

        let key = "\(address.kind)|\(address.normalizedValue)|\(callIdentifier)"
        guard loadedCustomerContextKey != key else { return }

        loadedCustomerContextKey = key
        model.customerContextLoaded = false
        let displayName = customerDisplayName

        Task { [weak self] in
            let snapshot = await CustomerContextStore.shared.load(
                address: address,
                displayName: displayName,
                callIdentifier: callIdentifier
            )

            guard
                let self,
                self.loadedCustomerContextKey == key
            else {
                return
            }

            self.isApplyingCustomerContext = true
            self.model.customerCompany = snapshot.company
            self.model.customerKeys = snapshot.keys.joined(separator: ", ")
            self.model.customerEmails = snapshot.emails.joined(separator: ", ")
            self.model.customerNote = snapshot.currentCallNote
            self.model.previousConversationCount =
                snapshot.previousConversationCount
            self.model.lastCallDate = snapshot.lastCallDate
            self.model.recentCustomerNotes = snapshot.recentNotes
            self.model.customerContextLoaded = true
            self.isApplyingCustomerContext = false
        }
    }

    private func scheduleCustomerContextSave() {
        guard
            model.customerContextLoaded,
            !isApplyingCustomerContext
        else {
            return
        }

        customerContextSaveTask?.cancel()
        customerContextSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }

            self?.saveCustomerContextNow()
        }
    }

    private func saveCustomerContextNow() {
        guard
            !model.isTransfer,
            model.customerContextLoaded,
            !isApplyingCustomerContext,
            let callController,
            let address = customerPartyAddress,
            let callIdentifier = callController.identifier,
            !callIdentifier.isEmpty
        else {
            return
        }

        customerContextSaveTask?.cancel()
        customerContextSaveTask = nil

        let displayName = customerDisplayName
        let company = model.customerCompany
        let keys = listValues(model.customerKeys)
        let emails = listValues(model.customerEmails)
        let note = model.customerNote

        Task {
            await CustomerContextStore.shared.save(
                address: address,
                displayName: displayName,
                callIdentifier: callIdentifier,
                company: company,
                keys: keys,
                emails: emails,
                note: note
            )
        }
    }

    private func listValues(_ text: String) -> [String] {
        text.split { character in
            character == "," || character == ";" || character.isNewline
        }
        .map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    }
}

private final class DTMFCapturingHostingView<Content: View>: NSHostingView<Content> {
    var onText: ((String) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        guard
            !event.isARepeat,
            let characters = event.characters,
            let firstScalar = characters.unicodeScalars.first
        else {
            super.keyDown(with: event)
            return
        }

        let allowed = CharacterSet(charactersIn: "0123456789*#abcdrABCDR")
        guard allowed.contains(firstScalar) else {
            super.keyDown(with: event)
            return
        }

        onText?(characters)
    }
}
