//
//  CallWindowModel.swift
//  Telephone
//

import Foundation
import Observation
import UseCases

struct CallCommandState: Equatable {
    let phase: CallSession.Phase
    let muted: Bool
    let held: Bool
    let muteEnabled: Bool
    let holdEnabled: Bool
    let transferEnabled: Bool
    let incomingActionsEnabled: Bool
    let hangUpEnabled: Bool
    let redialEnabled: Bool
}

struct CallControlSnapshot: Equatable {
    let isConfirmed: Bool
    let isMicrophoneMuted: Bool
    let isOnLocalHold: Bool
    let isOnRemoteHold: Bool
}

@MainActor
@Observable
final class CallSession {
    enum Phase: Equatable {
        case incoming
        case active
        case ended
        case transferDestination
        case transferActive
        case transferEnded
    }

    var phase: Phase
    var showsProgress = false
    var incomingActionsEnabled = true

    var hangUpEnabled = true
    var muteEnabled = false
    var muted = false
    var holdEnabled = false
    var held = false
    var transferEnabled = false
    var redialEnabled = true

    let isTransfer: Bool

    @ObservationIgnored
    private var call: Call?

    @ObservationIgnored
    private let controlSnapshot: (Call) -> CallControlSnapshot?

    init(
        isTransfer: Bool,
        controlSnapshot: @escaping (Call) -> CallControlSnapshot? = { _ in nil }
    ) {
        self.isTransfer = isTransfer
        self.controlSnapshot = controlSnapshot
        phase = isTransfer ? .transferDestination : .active
    }

    func setCall(_ call: Call?) {
        self.call = call
        updateCallControls()
    }

    func showIncomingState() {
        guard !isTransfer else { return }

        phase = .incoming
        incomingActionsEnabled = true
        showsProgress = false
    }

    func showActiveState() {
        phase = isTransfer ? .transferActive : .active
    }

    func showEndedState() {
        phase = isTransfer ? .transferEnded : .ended
        showsProgress = false
    }

    func showTransferDestinationState() {
        guard isTransfer else { return }

        phase = .transferDestination
    }

    func updateCallControls() {
        guard
            let call,
            let controls = controlSnapshot(call)
        else {
            muted = false
            muteEnabled = false
            held = false
            holdEnabled = false
            transferEnabled = false
            return
        }

        muted = controls.isMicrophoneMuted
        muteEnabled = controls.isConfirmed
        held = controls.isOnLocalHold
        holdEnabled = controls.isConfirmed && !controls.isOnRemoteHold
        transferEnabled =
            !isTransfer && controls.isConfirmed && !controls.isOnRemoteHold
    }

    var commandState: CallCommandState {
        CallCommandState(
            phase: phase,
            muted: muted,
            held: held,
            muteEnabled: muteEnabled,
            holdEnabled: holdEnabled,
            transferEnabled: transferEnabled,
            incomingActionsEnabled: incomingActionsEnabled,
            hangUpEnabled: hangUpEnabled,
            redialEnabled: redialEnabled
        )
    }

    private func matches(_ eventCall: Call) -> Bool {
        guard let call else { return false }

        return ObjectIdentifier(call as AnyObject)
            == ObjectIdentifier(eventCall as AnyObject)
    }
}

// AKSIPCall notifications are delivered on the main thread. The
// @preconcurrency conformance bridges the legacy synchronous event-target
// protocol to the main-actor session without adding an unnecessary async hop.
extension CallSession: @preconcurrency CallEventTarget {
    func didMake(_ call: Call) {
        guard matches(call) else { return }

        showActiveState()
    }

    func didReceive(_ call: Call) {
        guard matches(call) else { return }

        showIncomingState()
    }

    func isConnecting(_ call: Call) {
        guard matches(call) else { return }

        showActiveState()
    }

    func didConnect(_ call: Call) {
        guard matches(call) else { return }

        showActiveState()
        showsProgress = false
        updateCallControls()
    }

    func didDisconnect(_ call: Call) {
        guard matches(call) else { return }

        showEndedState()
        incomingActionsEnabled = false
        hangUpEnabled = false
        updateCallControls()
    }
}

@MainActor
@Observable
final class CallWindowModel {
    // Session owns call phase and controls; this model owns window presentation.
    let session: CallSession

    var displayedName = ""
    var identityDetail = ""
    var contactOrganization = ""
    var status = ""

    static func outgoingStatus(phoneLabel: String) -> String {
        guard !phoneLabel.isEmpty else {
            return NSLocalizedString("calling...", comment: "Outgoing call in progress.")
        }
        return String(
            format: NSLocalizedString("calling %@...", comment: "Outgoing call in progress."),
            phoneLabel
        )
    }

    var windowTitle = NSLocalizedString("Call Window Title", comment: "Call window title.")
    var windowDismissEnabled = true

    var answerFocusRequest = 0
    var callSurfaceFocusRequest = 0

    var transferActionEnabled = false
    var transferCancelEnabled = true
    var transferPresentation: CallPresentationCoordinator?

    var usesDTMFDisplay = false

    var accountDescription = ""
    var showsAccountInfo = false
    var isTransfer: Bool { session.isTransfer }

    func showIncomingState() {
        session.showIncomingState()
    }

    func showActiveState() {
        session.showActiveState()
    }

    func showEndedState() {
        session.showEndedState()

        if !isTransfer {
            transferPresentation = nil
        }
    }

    func showTransferDestinationState() {
        guard isTransfer else { return }

        session.showTransferDestinationState()
        transferActionEnabled = false
    }

    func requestCallSurfaceFocus() {
        guard session.phase == .active || session.phase == .transferActive else {
            return
        }

        callSurfaceFocusRequest &+= 1
    }

    init(session: CallSession) {
        self.session = session
    }

    convenience init(isTransfer: Bool) {
        self.init(session: CallSession(isTransfer: isTransfer))
    }
}
