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
    private let model: CallWindowModel
    private let transferCoordinator: CallTransferCoordinator
    private let customerContextCoordinator: CustomerContextCoordinator?

    private var accountInfoObservation: NSKeyValueObservation?
    private var callTimer: Foundation.Timer?
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
        customerContextCoordinator?.invalidate()
        accountInfoObservation?.invalidate()
        accountInfoObservation = nil
        CallPresentationRegistry.shared.unregister(key: id)
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
        transferCoordinator.resetForCallChange()
        enteredDTMF = NSMutableString()
        model.usesDTMFDisplay = false
        updateCallControls()

        if call != nil {
            customerContextCoordinator?.loadIfNeeded()
        }
    }

    func setDisplayedName(_ value: String) {
        model.displayedName = value
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

    @objc
    func enableRedialButtonTick(_ timer: Foundation.Timer) {
        model.redialEnabled = true
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

        callController.status = value
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
