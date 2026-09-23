//
//  CallContentViewController.swift
//  Telephone
//

import AppKit
import SwiftUI

@MainActor
@objcMembers
final class CallContentViewController: NSObject, Identifiable {
    @nonobjc let id: String

    private weak var callController: CallController?
    private weak var accountController: AccountController?
    private let model: CallWindowModel
    private let transferDestinationComposer: CallDestinationComposer?

    private var accountInfoObservation: NSKeyValueObservation?
    private var callTimer: Foundation.Timer?
    private var enteredDTMF = NSMutableString()
    private var waitingForTransferHold = false

    private var customerContextSaveTask: Task<Void, Never>?
    private var loadedCustomerContextKey: String?
    private var isApplyingCustomerContext = false
    private var didNotifyWindowClose = false

    class func installScene() {
        CallWindowSceneController.shared.install()
    }

    @objc(initWithCallController:accountController:isTransfer:)
    init(
        callController: CallController,
        accountController: AccountController,
        isTransfer: Bool
    ) {
        id = callController.identifier
        self.callController = callController
        self.accountController = accountController

        let model = CallWindowModel(isTransfer: isTransfer)
        model.accountDescription = accountController.accountDescription
        model.showsAccountInfo =
            !isTransfer && accountController.callsShouldDisplayAccountInfo
        model.windowTitle = isTransfer
            ? NSLocalizedString(
                "Call Transfer",
                comment: "Call transfer window title."
            )
            : NSLocalizedString("Call", comment: "Window title.")
        self.model = model

        transferDestinationComposer = isTransfer
            ? CallDestinationComposer(accountController: accountController)
            : nil

        super.init()

        CallWindowRegistry.shared.register(self)

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

    @nonobjc
    var contentView: some View {
        CallWindowView(
            model: model,
            transferDestinationComposer: transferDestinationComposer,
            answer: { [weak self] in self?.acceptCall(nil) },
            decline: { [weak self] in self?.hangUpCall(nil) },
            hangUp: { [weak self] in self?.hangUpCall(nil) },
            toggleMute: { [weak self] in self?.toggleMicrophoneMute(nil) },
            toggleHold: { [weak self] in self?.toggleCallHold(nil) },
            showTransfer: { [weak self] in self?.showCallTransferSheet(nil) },
            redial: { [weak self] in self?.redial(nil) },
            callTransferDestination: { [weak self] in
                self?.callTransferDestination()
            },
            closeTransfer: { [weak self] in
                self?.closeTransferSheet()
            },
            cancelTransfer: { [weak self] in
                self?.cancelTransfer()
            },
            completeTransfer: { [weak self] in
                self?.completeTransfer()
            },
            customerContextChanged: { [weak self] in
                self?.scheduleCustomerContextSave()
            },
            sendDTMF: { [weak self] text in
                self?.handleDTMF(text)
            }
        )
        .onDisappear { [weak self] in
            self?.windowDidDisappear()
        }
    }

    func showWindow() {
        guard !model.isTransfer else { return }
        didNotifyWindowClose = false
        CallWindowSceneController.shared.show(key: id)
    }

    func closeWindow() {
        guard !model.isTransfer else { return }
        CallWindowSceneController.shared.hide(key: id)
    }

    func setWindowTitle(_ value: String) {
        model.windowTitle = value.isEmpty
            ? NSLocalizedString("Call", comment: "Window title.")
            : value
    }

    func setWindowDismissEnabled(_ enabled: Bool) {
        model.windowDismissEnabled = enabled
    }

    func dismissTransfer() {
        model.transferPresentation = nil
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
        if !model.isTransfer {
            model.transferPresentation = nil
        }
        stopCallTimer()
        loadCustomerContextIfNeeded()
    }

    func showTransferDestinationState() {
        guard model.isTransfer else { return }
        waitingForTransferHold = false
        model.phase = .transferDestination
        model.transferActionEnabled = false
        transferDestinationComposer?.focus()
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
        transferDestinationComposer?.focus()
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
            let transferController = callController.callTransferController,
            let presentation = CallWindowRegistry.shared.presentation(
                for: transferController.identifier
            )
        else {
            return
        }

        presentation.showTransferDestinationState()
        model.transferPresentation = presentation
    }

    @IBAction func redial(_ sender: Any?) {
        callController?.redial()
    }

    private func callTransferDestination() {
        guard
            let transferDestinationComposer,
            let transferController = callController as? CallTransferController
        else {
            return
        }

        transferDestinationComposer.makeCall(
            callTransferController: transferController
        )
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

    private func closeTransferSheet() {
        guard let transferController = callController as? CallTransferController else {
            return
        }

        transferController.closeSheet(nil)
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

        model.callSurfaceFocusRequest &+= 1
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
            setWindowTitle(callController.displayedName)
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

    private func windowDidDisappear() {
        guard !model.isTransfer, !didNotifyWindowClose else { return }

        didNotifyWindowClose = true
        saveCustomerContextNow()
        callController?.callWindowDidClose()
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


@MainActor
private final class CallWindowRegistry {
    static let shared = CallWindowRegistry()

    private final class WeakPresentation {
        weak var value: CallContentViewController?

        init(_ value: CallContentViewController) {
            self.value = value
        }
    }

    private var presentations: [String: WeakPresentation] = [:]

    func register(_ presentation: CallContentViewController) {
        presentations[presentation.id] = WeakPresentation(presentation)
    }

    func presentation(for key: String) -> CallContentViewController? {
        guard let presentation = presentations[key]?.value else {
            presentations[key] = nil
            return nil
        }
        return presentation
    }
}

private struct CallWindowsScene: Scene {
    @AppStorage(UserDefaultsKeys.keepCallWindowOnTop)
    private var keepOnTop = false

    var body: some Scene {
        WindowGroup(
            NSLocalizedString(
                "Call",
                comment: "Call window scene title."
            ),
            id: CallWindowSceneController.sceneID,
            for: String.self
        ) { key in
            if let key = key.wrappedValue,
               let presentation = CallWindowRegistry.shared.presentation(
                   for: key
               ) {
                presentation.contentView
            } else {
                EmptyView()
            }
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowBackgroundDragBehavior(.enabled)
        .windowLevel(keepOnTop ? .floating : .normal)
    }
}

@MainActor
private final class CallWindowSceneController {
    static let shared = CallWindowSceneController()
    static let sceneID = "telephone-call"

    private let representation = NSHostingSceneRepresentation {
        CallWindowsScene()
    }
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        NSApplication.shared.addSceneRepresentation(representation)
    }

    func show(key: String) {
        representation.environment.openWindow(
            id: Self.sceneID,
            value: key
        )
    }

    func hide(key: String) {
        representation.environment.dismissWindow(
            id: Self.sceneID,
            value: key
        )
    }
}
