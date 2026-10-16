//
//  CallPresentationCoordinator.swift
//  Telephone
//

import Foundation
import OSLog
import SwiftUI

@MainActor
final class CallPresentationCoordinator: Identifiable {
    let id: String

    private weak var callController: CallController?
    private let session: CallSession
    private let callEventSource: AKSIPCallEventSource
    private let model: CallWindowModel
    private let transferCoordinator: CallTransferCoordinator
    private let crmKeyLookupModel: CRMKeyLookupModel?
    private var customerDetailsWindow: CallCustomerDetailsWindowController?

    private let clock = ContinuousClock()
    private var callTimerTask: Task<Void, Never>?
    private var redialEnableTask: Task<Void, Never>?
    private var autoCloseTask: Task<Void, Never>?
    private var intermediateStatusTask: Task<Void, Never>?
    private var enteredDTMF = ""
    private var closeNotificationGate = CallWindowCloseNotificationGate()
    private var activeCallInterval: OSSignpostIntervalState?

    init(
        callController: CallController,
        accountController: AccountController,
        isTransfer: Bool
    ) {
        id = callController.identifier
        self.callController = callController

        let session = CallSession(isTransfer: isTransfer) { call in
            guard let call = call as? AKSIPCall else { return nil }

            return CallControlSnapshot(
                isConfirmed: call.isConfirmed,
                isMicrophoneMuted: call.isMicrophoneMuted,
                isOnLocalHold: call.isOnLocalHold,
                isOnRemoteHold: call.isOnRemoteHold
            )
        }
        self.session = session
        callEventSource = AKSIPCallEventSource(
            center: .default,
            target: session
        )

        let model = CallWindowModel(session: session)
        model.accountDescription = accountController.accountDescription
        model.showsAccountInfo =
            !isTransfer && accountController.callsShouldDisplayAccountInfo
        model.windowTitle = isTransfer
            ? NSLocalizedString(
                "Call Transfer",
                comment: "Call transfer window title."
            )
            : NSLocalizedString("Call Window Title", comment: "Call window title.")
        self.model = model

        crmKeyLookupModel = isTransfer ? nil : CRMKeyLookupModel(
            settings: accountController.crmGatewaySettings,
            provider: accountController.crmKeyLookupProvider,
            appendRegistry: accountController.crmPhoneAppendRegistry
        )

        transferCoordinator = CallTransferCoordinator(
            callController: callController,
            accountController: accountController,
            model: model
        )
        CallPresentationRegistry.shared.register(self, key: id)
    }

    var contentView: some View {
        CallWindowView(
            model: model,
            transferDestinationComposer: transferCoordinator.destinationComposer,
            crmKeyLookupModel: crmKeyLookupModel,
            answer: { [weak self] in self?.acceptCall() },
            decline: { [weak self] in self?.hangUpCall() },
            hangUp: { [weak self] in self?.hangUpCall() },
            toggleMute: { [weak self] in self?.toggleMicrophoneMute() },
            toggleHold: { [weak self] in self?.toggleCallHold() },
            showTransfer: { [weak self] in self?.showCallTransfer() },
            redial: { [weak self] in self?.redial() },
            callTransferDestination: { [weak self] in
                self?.transferCoordinator.callDestination()
            },
            closeTransfer: { [weak self] in
                self?.transferCoordinator.closeSheet()
            },
            cancelTransfer: { [weak self] in
                self?.transferCoordinator.cancel()
            },
            completeTransfer: { [weak self] in
                self?.transferCoordinator.complete()
            },
            showCustomerDetails: { [weak self] in self?.showCustomerDetails() },
            sendDTMF: { [weak self] text in
                self?.handleDTMF(text)
            }
        )
        .focusedSceneValue(\.callCommandTarget, self)
        .onDisappear { [weak self] in
            self?.windowDidDisappear()
        }
    }

    func showWindow() {
        guard !model.isTransfer else { return }
        updateCRMCallerPhone()
        closeNotificationGate.reset()
        SceneRouter.shared.openWindow(
            id: CallWindowScene.id,
            value: id
        )
    }

    func closeWindow() {
        guard !model.isTransfer else { return }
        closeCustomerDetails()
        SceneRouter.shared.dismissWindow(
            id: CallWindowScene.id,
            value: id
        )
    }

    func invalidate() {
        closeCustomerDetails()
        PerformanceStateReporting.removeCall(id: id)
        endActiveCallInterval()
        stopCallTimer()
        cancelRedialEnable()
        cancelAutoClose()
        cancelIntermediateStatusRestore()
        crmKeyLookupModel?.resetContext()
        CallPresentationRegistry.shared.unregister(key: id)
    }

    func setShowsAccountInfo(_ visible: Bool) {
        model.showsAccountInfo = !model.isTransfer && visible
    }

    func setWindowTitle(_ value: String) {
        model.windowTitle = value.isEmpty
            ? NSLocalizedString("Call Window Title", comment: "Call window title.")
            : value
    }

    func setWindowDismissEnabled(_ enabled: Bool) {
        model.windowDismissEnabled = enabled
    }

    func dismissTransfer() {
        model.transferPresentation = nil
    }

    func setCall(_ call: AKSIPCall?) {
        closeCustomerDetails()
        stopCallTimer()
        cancelRedialEnable()
        cancelIntermediateStatusRestore()
        crmKeyLookupModel?.resetContext()
        transferCoordinator.discardSourceTransferSession()
        session.setCall(call)
        updateCRMCallerPhone()
        enteredDTMF = ""
        model.usesDTMFDisplay = false
    }

    func setDisplayedName(_ value: String) {
        model.displayedName = DisplayNameText.normalized(value)
    }

    func setIdentityDetail(_ value: String) {
        model.identityDetail = DisplayNameText.normalized(value)
    }

    func setContactOrganization(_ value: String) {
        model.contactOrganization = DisplayNameText.normalized(value)
    }

    func setStatus(_ value: String) {
        model.status = value
    }

    func showIncomingState() {
        model.showIncomingState()
        PerformanceStateReporting.showIncomingCall(id: id)
        focusAnswer()
    }

    func showActiveState() {
        model.showActiveState()
        beginActiveCallIntervalIfNeeded()
        updateCallControls()
        model.requestCallSurfaceFocus()
    }

    func showEndedState() {
        transferCoordinator.discardSourceTransferSession()
        model.showEndedState()
        PerformanceStateReporting.showEndedCall(id: id)
        endActiveCallInterval()
        stopCallTimer()
        cancelIntermediateStatusRestore()
    }

    func showTransferDestinationState() {
        transferCoordinator.showDestinationState()
    }

    func setProgressVisible(_ visible: Bool) {
        session.showsProgress = visible
        updateCallControls()
    }

    func setHangUpEnabled(_ enabled: Bool) {
        session.hangUpEnabled = enabled
        if model.isTransfer {
            model.transferCancelEnabled = enabled
        }
    }

    func setIncomingActionsEnabled(_ enabled: Bool) {
        session.incomingActionsEnabled = enabled
    }

    func setRedialEnabled(_ enabled: Bool) {
        session.redialEnabled = enabled
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
        transferCoordinator.focusDestination()
    }

    func updateCallControls() {
        session.updateCallControls()

        if !model.isTransfer, let call = callController?.call, call.isActive {
            PerformanceStateReporting.showActiveCall(
                id: id,
                isHeld: call.isOnLocalHold || call.isOnRemoteHold
            )
        }

        if model.isTransfer {
            model.transferActionEnabled = session.holdEnabled
        }
    }

    func startCallTimer() {
        guard callTimerTask == nil else { return }

        updateCallDuration()

        let clock = clock
        callTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: .seconds(1))
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                self?.updateCallDuration()
            }
        }
    }

    func stopCallTimer() {
        callTimerTask?.cancel()
        callTimerTask = nil
    }

    func scheduleRedialEnable(after delay: TimeInterval) {
        cancelRedialEnable()

        let clock = clock
        let duration = sleepDuration(for: delay)
        redialEnableTask = Task { @MainActor [weak self] in
            do {
                try await clock.sleep(for: duration)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else { return }
            redialEnableTask = nil
            session.redialEnabled = true
        }
    }

    func scheduleAutoClose(after delay: TimeInterval) {
        cancelAutoClose()

        let clock = clock
        let duration = sleepDuration(for: delay)
        autoCloseTask = Task { @MainActor [weak self] in
            do {
                try await clock.sleep(for: duration)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else { return }
            autoCloseTask = nil
            callController?.close()
        }
    }

    func cancelAutoClose() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
    }

    func showIntermediateStatus(_ value: String) {
        cancelIntermediateStatusRestore()
        stopCallTimer()
        callController?.status = value

        let clock = clock
        let duration = sleepDuration(for: 3)
        intermediateStatusTask = Task { @MainActor [weak self] in
            do {
                try await clock.sleep(for: duration)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else { return }
            intermediateStatusTask = nil
            restoreStatusAfterIntermediateMessage()
        }
    }

    func callDidHoldForTransfer() {
        transferCoordinator.callDidHold()
    }

    func acceptCall() {
        callController?.acceptCall()
    }

    func hangUpCall() {
        callController?.hangUpCall()
    }

    func toggleCallHold() {
        guard let call = callController?.call else { return }
        callController?.setCallHeld(!call.isOnLocalHold)
        updateCallControls()
    }

    func toggleMicrophoneMute() {
        guard let call = callController?.call else { return }
        callController?.setMicrophoneMuted(!call.isMicrophoneMuted)
        updateCallControls()
    }

    func showCallTransfer() {
        transferCoordinator.showSheet()
    }

    func redial() {
        callController?.redial()
    }

    private func cancelRedialEnable() {
        redialEnableTask?.cancel()
        redialEnableTask = nil
    }

    private func cancelIntermediateStatusRestore() {
        intermediateStatusTask?.cancel()
        intermediateStatusTask = nil
    }

    private func sleepDuration(for interval: TimeInterval) -> Duration {
        .milliseconds(Int64((max(0, interval) * 1_000).rounded()))
    }

    private func restoreStatusAfterIntermediateMessage() {
        guard let callController, let call = callController.call else {
            return
        }

        if call.isOnLocalHold {
            callController.status = NSLocalizedString(
                "on hold",
                comment: "Call on local hold status text."
            )
        } else if call.isOnRemoteHold {
            callController.status = NSLocalizedString(
                "on remote hold",
                comment: "Call on remote hold status text."
            )
        } else if call.isMicrophoneMuted {
            callController.status = NSLocalizedString(
                "mic muted",
                comment: "Microphone muted status text."
            )
        } else if call.isActive {
            startCallTimer()
        }
    }

    private func beginActiveCallIntervalIfNeeded() {
        guard !model.isTransfer, activeCallInterval == nil else {
            return
        }

        let signpostID = PerformanceSignposts.calls.makeSignpostID(from: self)
        activeCallInterval = PerformanceSignposts.calls.beginInterval(
            "ActiveCall",
            id: signpostID
        )
    }

    private func endActiveCallInterval() {
        guard let activeCallInterval else {
            return
        }

        PerformanceSignposts.calls.endInterval(
            "ActiveCall",
            activeCallInterval
        )
        self.activeCallInterval = nil
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

        if callController.status != value {
            callController.status = value
        }
    }

    private func handleDTMF(_ text: String) {
        guard
            session.phase == .active || session.phase == .transferActive,
            let callController,
            let call = callController.call
        else {
            return
        }

        guard DTMFKeyRouting.shouldHandle(
            text,
            isCallSurfaceFocused: true
        ) else {
            return
        }

        if enteredDTMF.isEmpty {
            setWindowTitle(callController.displayedName ?? "")
            model.usesDTMFDisplay = true
        }

        enteredDTMF.append(text)
        callController.displayedName = enteredDTMF
        call.sendDTMF(text)
    }

    private func showCustomerDetails() {
        guard !model.isTransfer, let crmKeyLookupModel, crmKeyLookupModel.settings.enabled else {
            return
        }
        if customerDetailsWindow == nil {
            customerDetailsWindow = CallCustomerDetailsWindowController(
                model: model, crmKeyLookupModel: crmKeyLookupModel
            )
        }
        customerDetailsWindow?.present()
    }

    private func closeCustomerDetails() {
        customerDetailsWindow?.close()
        customerDetailsWindow = nil
    }

    private func windowDidDisappear() {
        guard
            !model.isTransfer,
            closeNotificationGate.consume()
        else {
            return
        }

        closeCustomerDetails()
        crmKeyLookupModel?.deactivateContext()
        callController?.callWindowDidClose()
    }

    private func updateCRMCallerPhone() {
        // Only the actual SIP peer user is eligible. Display names, headers and
        // arbitrary SIP usernames are never turned into CRM phone identities.
        let rawPhone = callController?.call?.remoteURI.user
        crmKeyLookupModel?.setCallerPhone(
            rawPhone, isActive: callController?.call != nil
        )
    }
}
