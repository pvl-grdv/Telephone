//
//  ActiveCallViewController.swift
//  Telephone
//

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
fileprivate final class ActiveCallModel {
    var displayedName = ""
    var status = ""
    var showsProgress = false
    var hangUpEnabled = true
    var muteEnabled = false
    var muted = false
    var holdEnabled = false
    var held = false
    var transferEnabled = false
    var transferActionEnabled = false
    var cancelEnabled = true
    var usesDTMFDisplay = false

    var customerCompany = ""
    var customerKeys = ""
    var customerEmails = ""
    var customerNote = ""
    var previousConversationCount = 0
    var lastCallDate: Date?
    var recentCustomerNotes: [CustomerContextNote] = []
    var customerContextLoaded = false
}

@MainActor
@objcMembers
class ActiveCallViewController: NSViewController, NSMenuItemValidation {
    weak var callController: CallController?
    var callTimer: Foundation.Timer?
    var enteredDTMF = NSMutableString()

    fileprivate let model = ActiveCallModel()
    private var displayedNameObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var customerContextSaveTask: Task<Void, Never>?
    private var isApplyingCustomerContext = false

    @objc(initWithNibName:callController:)
    init(nibName: String, callController: CallController) {
        self.callController = callController
        super.init(nibName: nil, bundle: nil)
        startObserving()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate var isTransferPresentation: Bool {
        self is ActiveCallTransferViewController
    }

    override func loadView() {
        let root = ActiveCallView(
            model: model,
            isTransfer: isTransferPresentation,
            hangUp: { [weak self] in self?.hangUpCall(nil) },
            toggleMute: { [weak self] in self?.toggleMicrophoneMute(nil) },
            toggleHold: { [weak self] in self?.toggleCallHold(nil) },
            showTransfer: { [weak self] in self?.showCallTransferSheet(nil) },
            cancelTransfer: { [weak self] in
                (self as? ActiveCallTransferViewController)?.cancelTransfer(nil)
            },
            completeTransfer: { [weak self] in
                (self as? ActiveCallTransferViewController)?.transferCall(nil)
            },
            customerContextChanged: { [weak self] in
                self?.scheduleCustomerContextSave()
            }
        )

        let hostingView = DTMFCapturingHostingView(rootView: root)
        hostingView.onText = { [weak self] text in
            self?.handleDTMF(text)
        }
        view = hostingView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateCallControls()
        loadCustomerContext()
    }

    override func viewWillDisappear() {
        saveCustomerContextNow()
        super.viewWillDisappear()
    }

    func removeObservations() {
        displayedNameObservation?.invalidate()
        statusObservation?.invalidate()
        displayedNameObservation = nil
        statusObservation = nil
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
        guard let callController else { return }

        if !callController.isCallOnHold {
            callController.setCallHeld(true)
        }

        let transferController = callController.callTransferController
        guard
            let transferWindow = transferController?.window,
            let parentWindow = callController.window
        else {
            return
        }
        parentWindow.beginSheet(transferWindow)
    }

    func startCallTimer() {
        guard callTimer?.isValid != true else { return }

        callTimer = Foundation.Timer.scheduledTimer(
            timeInterval: 0.2,
            target: self,
            selector: #selector(callTimerTick(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    func stopCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
    }

    @objc func callTimerTick(_ timer: Foundation.Timer) {
        guard let callController else { return }

        let seconds = Int(Date.timeIntervalSinceReferenceDate - callController.callStartTime)
        if seconds < 3600 {
            callController.status = String(
                format: "%02d:%02d",
                (seconds / 60) % 60,
                seconds % 60
            )
        } else {
            callController.status = String(
                format: "%02d:%02d:%02d",
                (seconds / 3600) % 24,
                (seconds / 60) % 60,
                seconds % 60
            )
        }
    }

    func showProgress() {
        model.showsProgress = true
        updateCallControls()
    }

    func showHangUp() {
        model.showsProgress = false
        updateCallControls()
    }

    func allowHangUp() {
        model.hangUpEnabled = true
    }

    func disallowHangUp() {
        model.hangUpEnabled = false
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
        model.transferEnabled = confirmed && !call.isOnRemoteHold
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleMicrophoneMute(_:)):
            menuItem.title = model.muted
                ? NSLocalizedString("Unmute", comment: "Unmute. Call menu item.")
                : NSLocalizedString("Mute", comment: "Mute. Call menu item.")
            return model.muteEnabled

        case #selector(toggleCallHold(_:)):
            menuItem.title = model.held
                ? NSLocalizedString("Resume", comment: "Resume. Call menu item.")
                : NSLocalizedString("Hold", comment: "Hold. Call menu item.")
            return model.holdEnabled

        case #selector(showCallTransferSheet(_:)):
            return model.transferEnabled

        case #selector(hangUpCall(_:)):
            menuItem.title = NSLocalizedString("End Call", comment: "End Call. Call menu item.")
            return model.hangUpEnabled

        default:
            return true
        }
    }

    private var customerPartyAddress: CustomerPartyAddress? {
        guard let callController else { return nil }

        if let uri = callController.call?.remoteURI ?? callController.redialURI {
            return CustomerPartyAddress(user: uri.user, host: uri.host)
        }

        let entered = callController.enteredCallDestination
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entered.isEmpty else { return nil }
        return CustomerPartyAddress(user: entered, host: "")
    }

    private var customerDisplayName: String {
        guard let callController else { return "" }
        if !callController.nameFromAddressBook.isEmpty {
            return callController.nameFromAddressBook
        }
        return callController.displayedName
    }

    private func loadCustomerContext() {
        guard
            !isTransferPresentation,
            let callController,
            let address = customerPartyAddress
        else {
            return
        }

        guard
            let callIdentifier = callController.identifier,
            !callIdentifier.isEmpty
        else {
            return
        }
        let displayName = customerDisplayName

        Task { [weak self] in
            let snapshot = await CustomerContextStore.shared.load(
                address: address,
                displayName: displayName,
                callIdentifier: callIdentifier
            )

            guard let self, self.customerPartyAddress == address else {
                return
            }

            self.isApplyingCustomerContext = true
            self.model.customerCompany = snapshot.company
            self.model.customerKeys = snapshot.keys.joined(separator: ", ")
            self.model.customerEmails = snapshot.emails.joined(separator: ", ")
            self.model.customerNote = snapshot.currentCallNote
            self.model.previousConversationCount = snapshot.previousConversationCount
            self.model.lastCallDate = snapshot.lastCallDate
            self.model.recentCustomerNotes = snapshot.recentNotes
            self.model.customerContextLoaded = true
            self.isApplyingCustomerContext = false
        }
    }

    private func scheduleCustomerContextSave() {
        guard !isApplyingCustomerContext else { return }

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
            !isTransferPresentation,
            !isApplyingCustomerContext,
            let callController,
            let address = customerPartyAddress
        else {
            return
        }

        customerContextSaveTask?.cancel()
        customerContextSaveTask = nil

        guard
            let callIdentifier = callController.identifier,
            !callIdentifier.isEmpty
        else {
            return
        }
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

    private func startObserving() {
        guard let callController else { return }

        displayedNameObservation = callController.observe(
            \.displayedName,
            options: [.initial, .new]
        ) { [weak self] controller, _ in
            let value = controller.displayedName ?? ""
            Task { @MainActor [weak self] in
                self?.model.displayedName = value
            }
        }

        statusObservation = callController.observe(
            \.status,
            options: [.initial, .new]
        ) { [weak self] controller, _ in
            let value = controller.status ?? ""
            Task { @MainActor [weak self] in
                self?.model.status = value
            }
        }
    }

    private func handleDTMF(_ text: String) {
        let allowed = CharacterSet(charactersIn: "0123456789*#abcdrABCDR")
        guard text.unicodeScalars.allSatisfy(allowed.contains) else { return }
        guard let callController, let call = callController.call else { return }

        if enteredDTMF.length == 0 {
            view.window?.title = callController.displayedName
            model.usesDTMFDisplay = true
        }

        enteredDTMF.append(text)
        callController.displayedName = enteredDTMF as String
        call.sendDTMFDigits(text)
    }
}

@MainActor
@objcMembers
final class ActiveCallTransferViewController: ActiveCallViewController {
    private var waitingForHold = false

    override var representedObject: Any? {
        didSet {
            waitingForHold = false
        }
    }

    @IBAction func transferCall(_ sender: Any?) {
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
            disallowTransfer()
            waitingForHold = true
        }
    }

    func callDidHold() {
        guard
            waitingForHold,
            let transferController = callController as? CallTransferController
        else {
            return
        }

        transferController.transferCall()
        waitingForHold = false
    }

    func allowTransfer() {
        model.transferActionEnabled = true
    }

    func disallowTransfer() {
        model.transferActionEnabled = false
    }

    @IBAction func cancelTransfer(_ sender: Any?) {
        guard let transferController = callController as? CallTransferController else { return }
        transferController.showInitialState(sender)
    }

    override func showCallTransferSheet(_ sender: Any?) {
        // A transfer target cannot open another transfer sheet.
    }

    override func allowHangUp() {
        super.allowHangUp()
        model.cancelEnabled = true
    }

    override func disallowHangUp() {
        super.disallowHangUp()
        model.cancelEnabled = false
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(showCallTransferSheet(_:)) {
            return false
        }
        return super.validateMenuItem(menuItem)
    }
}

private struct ActiveCallView: View {
    @Bindable var model: ActiveCallModel

    let isTransfer: Bool
    let hangUp: () -> Void
    let toggleMute: () -> Void
    let toggleHold: () -> Void
    let showTransfer: () -> Void
    let cancelTransfer: () -> Void
    let completeTransfer: () -> Void
    let customerContextChanged: () -> Void

    var body: some View {
        if isTransfer {
            transferBody
                .frame(width: 320, height: 115)
        } else {
            regularBody
                .frame(width: 380, height: 238)
                .onChange(of: model.customerCompany) {
                    customerContextChanged()
                }
                .onChange(of: model.customerKeys) {
                    customerContextChanged()
                }
                .onChange(of: model.customerEmails) {
                    customerContextChanged()
                }
                .onChange(of: model.customerNote) {
                    customerContextChanged()
                }
        }
    }

    private var regularBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(model.displayedName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(model.usesDTMFDisplay ? .head : .tail)

                Spacer(minLength: 8)

                if model.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(action: hangUp) {
                    Image(systemName: "phone.down.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!model.hangUpEnabled)
                .help(NSLocalizedString("End Call", comment: "End call button."))
            }

            HStack(spacing: 8) {
                Text(model.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                CallControlButton(
                    systemImage: model.muted ? "mic.slash.fill" : "mic.fill",
                    help: model.muted
                        ? NSLocalizedString("Unmute", comment: "Unmute. Call menu item.")
                        : NSLocalizedString("Mute", comment: "Mute. Call menu item."),
                    isEnabled: model.muteEnabled,
                    action: toggleMute
                )

                CallControlButton(
                    systemImage: model.held ? "play.fill" : "pause.fill",
                    help: model.held
                        ? NSLocalizedString("Resume", comment: "Resume. Call menu item.")
                        : NSLocalizedString("Hold", comment: "Hold. Call menu item."),
                    isEnabled: model.holdEnabled,
                    action: toggleHold
                )

                CallControlButton(
                    systemImage: "arrow.right",
                    help: NSLocalizedString("Transfer", comment: "Transfer. Call menu item."),
                    isEnabled: model.transferEnabled,
                    action: showTransfer
                )
            }

            Divider()

            CustomerContextView(model: model)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var transferBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayedName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(model.usesDTMFDisplay ? .head : .tail)

                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if model.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 4)

            HStack {
                Spacer()

                Button(
                    NSLocalizedString("Cancel", comment: "Cancel button."),
                    action: cancelTransfer
                )
                .keyboardShortcut(.cancelAction)
                .disabled(!model.cancelEnabled)

                Button(
                    NSLocalizedString("Transfer", comment: "Transfer call button."),
                    action: completeTransfer
                )
                .keyboardShortcut(.defaultAction)
                .disabled(!model.transferActionEnabled)
            }
        }
        .padding(14)
    }
}

private struct CustomerContextView: View {
    @Bindable var model: ActiveCallModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(
                    NSLocalizedString(
                        "Client",
                        comment: "Local customer context section title."
                    ),
                    systemImage: "person.crop.circle"
                )
                .font(.caption.weight(.semibold))

                Spacer(minLength: 4)

                if model.customerContextLoaded {
                    Text(historySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            HStack(spacing: 6) {
                TextField(
                    NSLocalizedString(
                        "Organization",
                        comment: "Local customer organization field placeholder."
                    ),
                    text: $model.customerCompany
                )

                TextField(
                    NSLocalizedString(
                        "CRM keys",
                        comment: "Local customer CRM keys field placeholder."
                    ),
                    text: $model.customerKeys
                )
                .help(
                    NSLocalizedString(
                        "Separate multiple keys with commas.",
                        comment: "CRM keys field help."
                    )
                )
            }
            .disabled(!model.customerContextLoaded)

            TextField(
                NSLocalizedString(
                    "Email addresses",
                    comment: "Local customer email field placeholder."
                ),
                text: $model.customerEmails
            )
            .help(
                NSLocalizedString(
                    "Separate multiple email addresses with commas.",
                    comment: "Customer email field help."
                )
            )
            .disabled(!model.customerContextLoaded)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.customerNote)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(3)

                if model.customerNote.isEmpty {
                    Text(
                        NSLocalizedString(
                            "Notes for this call",
                            comment: "Call note editor placeholder."
                        )
                    )
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 52)
            .disabled(!model.customerContextLoaded)
            .background(.background, in: .rect(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.separator, lineWidth: 0.5)
            }

            if let recent = model.recentCustomerNotes.first {
                Text(
                    String(
                        format: NSLocalizedString(
                            "Previous note: %@",
                            comment: "Most recent previous customer note."
                        ),
                        recent.body
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(recent.body)
            }
        }
    }

    private var historySummary: String {
        guard model.previousConversationCount > 0 else {
            return NSLocalizedString(
                "No previous conversations",
                comment: "Customer has no previous conversations in Telephone."
            )
        }

        if let lastCallDate = model.lastCallDate {
            let date = lastCallDate.formatted(
                date: .abbreviated,
                time: .omitted
            )
            return String(
                format: NSLocalizedString(
                    "%ld previous · %@",
                    comment: "Previous conversations count and most recent date."
                ),
                model.previousConversationCount,
                date
            )
        }

        return String(
            format: NSLocalizedString(
                "%ld previous conversations",
                comment: "Previous conversations count."
            ),
            model.previousConversationCount
        )
    }
}

private struct CallControlButton: View {
    let systemImage: String
    let help: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.bordered)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(help)
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
