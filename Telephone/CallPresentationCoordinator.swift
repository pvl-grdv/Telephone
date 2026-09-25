//
//  CallPresentationCoordinator.swift
//  Telephone
//

import Foundation
import OSLog
import SwiftUI

@MainActor
@objcMembers
final class CallPresentationCoordinator: NSObject, Identifiable {
    @nonobjc let id: String

    private weak var callController: CallController?
    private let session: CallSession
    private let callEventSource: AKSIPCallEventSource
    private let model: CallWindowModel
    private let transferCoordinator: CallTransferCoordinator
    private let customerContextCoordinator: CustomerContextCoordinator?

    private var accountInfoObservation: NSKeyValueObservation?
    private let clock = ContinuousClock()
    private var callTimerTask: Task<Void, Never>?
    private var redialEnableTask: Task<Void, Never>?
    private var autoCloseTask: Task<Void, Never>?
    private var intermediateStatusTask: Task<Void, Never>?
    private var enteredDTMF = NSMutableString()
    private var closeNotificationGate = CallWindowCloseNotificationGate()
    private var activeCallInterval: OSSignpostIntervalState?

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

        transferCoordinator = CallTransferCoordinator(
            callController: callController,
            accountController: accountController,
            model: model
        )
        customerContextCoordinator = isTransfer
            ? nil
            : CustomerContextCoordinator(
                callController: callController,
                model: model
            )

        super.init()

        CallPresentationRegistry.shared.register(self, key: id)

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
            transferDestinationComposer: transferCoordinator.destinationComposer,
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
            customerContextChanged: { [weak self] in
                self?.customerContextCoordinator?.scheduleSave()
            },
            customerContextVisibilityChanged: { [weak self] isVisible in
                self?.customerContextCoordinator?
                    .visibilityChanged(isVisible)
            },
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
        closeNotificationGate.reset()
        CallWindowSceneController.shared.show(key: id)
    }

    func closeWindow() {
        guard !model.isTransfer else { return }
        CallWindowSceneController.shared.hide(key: id)
    }

    func invalidate() {
        endActiveCallInterval()
        stopCallTimer()
        cancelRedialEnable()
        cancelAutoClose()
        cancelIntermediateStatusRestore()
        customerContextCoordinator?.invalidate()
        accountInfoObservation?.invalidate()
        accountInfoObservation = nil
        CallPresentationRegistry.shared.unregister(key: id)
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
        stopCallTimer()
        cancelRedialEnable()
        cancelIntermediateStatusRestore()
        session.setCall(call)
        transferCoordinator.resetForCallChange()
        enteredDTMF = NSMutableString()
        model.usesDTMFDisplay = false

        if call != nil {
            customerContextCoordinator?.loadIfNeeded()
        }
    }

    func setDisplayedName(_ value: String) {
        model.displayedName = value
    }

    func setIdentityDetail(_ value: String) {
        model.identityDetail = value
    }

    func setContactOrganization(_ value: String) {
        model.contactOrganization = value
        if model.customerContextLoaded && model.customerCompany.isEmpty {
            model.customerCompany = value
        }
    }

    func setStatus(_ value: String) {
        model.status = value
    }

    func showIncomingState() {
        model.showIncomingState()
        customerContextCoordinator?.loadIfNeeded()
        focusAnswer()
    }

    func showActiveState() {
        model.showActiveState()
        beginActiveCallIntervalIfNeeded()
        updateCallControls()
        customerContextCoordinator?.loadIfNeeded()
        model.requestCallSurfaceFocus()
    }

    func showEndedState() {
        model.showEndedState()
        endActiveCallInterval()
        stopCallTimer()
        cancelIntermediateStatusRestore()
        customerContextCoordinator?.loadIfNeeded()
    }

    func showTransferDestinationState() {
        transferCoordinator.showDestinationState()
    }

    func setProgressVisible(_ visible: Bool) {
        model.showsProgress = visible
        updateCallControls()
    }

    func setHangUpEnabled(_ enabled: Bool) {
        model.hangUpEnabled = enabled
        if model.isTransfer {
            transferCoordinator.setCancelEnabled(enabled)
        }
    }

    func setIncomingActionsEnabled(_ enabled: Bool) {
        model.incomingActionsEnabled = enabled
    }

    func setRedialEnabled(_ enabled: Bool) {
        model.redialEnabled = enabled
    }

    func setTransferActionEnabled(_ enabled: Bool) {
        transferCoordinator.setActionEnabled(enabled)
    }

    func setTransferCancelEnabled(_ enabled: Bool) {
        transferCoordinator.setCancelEnabled(enabled)
    }

    func focusAnswer() {
        model.answerFocusRequest &+= 1
    }

    func focusTransferDestination() {
        transferCoordinator.focusDestination()
    }

    func updateCallControls() {
        session.updateCallControls()

        if model.isTransfer {
            transferCoordinator.setActionEnabled(session.holdEnabled)
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

    @objc(scheduleRedialEnableAfter:)
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
            model.redialEnabled = true
        }
    }

    @objc(scheduleAutoCloseAfter:)
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

    @objc(showIntermediateStatus:)
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
            model.phase == .active || model.phase == .transferActive,
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

        if enteredDTMF.length == 0 {
            setWindowTitle(callController.displayedName ?? "")
            model.usesDTMFDisplay = true
        }

        enteredDTMF.append(text)
        callController.displayedName = enteredDTMF as String
        call.sendDTMFDigits(text)
    }

    private func windowDidDisappear() {
        guard
            !model.isTransfer,
            closeNotificationGate.consume()
        else {
            return
        }

        customerContextCoordinator?.saveNow(ignoringPreference: true)
        callController?.callWindowDidClose()
    }
}
