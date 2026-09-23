//
//  CallWindowModel.swift
//  Telephone
//

import Foundation
import Observation

struct CallCommandState: Equatable {
    let phase: CallWindowModel.Phase
    let muted: Bool
    let held: Bool
    let muteEnabled: Bool
    let holdEnabled: Bool
    let transferEnabled: Bool
    let incomingActionsEnabled: Bool
    let hangUpEnabled: Bool
    let redialEnabled: Bool
}

@MainActor
@Observable
final class CallWindowModel {
    enum Phase: Equatable {
        case incoming
        case active
        case ended
        case transferDestination
        case transferActive
        case transferEnded
    }

    var phase: Phase
    var displayedName = ""
    var status = ""
    var windowTitle = NSLocalizedString("Call", comment: "Window title.")
    var windowDismissEnabled = true

    var showsProgress = false
    var incomingActionsEnabled = true
    var answerFocusRequest = 0
    var callSurfaceFocusRequest = 0

    var hangUpEnabled = true
    var muteEnabled = false
    var muted = false
    var holdEnabled = false
    var held = false
    var transferEnabled = false

    var transferActionEnabled = false
    var transferCancelEnabled = true
    var transferPresentation: CallPresentationCoordinator?
    var redialEnabled = true
    var usesDTMFDisplay = false

    var accountDescription = ""
    var showsAccountInfo = false
    let isTransfer: Bool

    var customerCompany = ""
    var customerKeys = ""
    var customerEmails = ""
    var customerNote = ""
    var previousConversationCount = 0
    var lastCallDate: Date?
    var recentCustomerNotes: [CustomerContextNote] = []
    var customerContextLoaded = false

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

        if !isTransfer {
            transferPresentation = nil
        }
    }

    func showTransferDestinationState() {
        guard isTransfer else { return }

        phase = .transferDestination
        transferActionEnabled = false
    }

    func requestCallSurfaceFocus() {
        guard phase == .active || phase == .transferActive else {
            return
        }

        callSurfaceFocusRequest &+= 1
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

    init(isTransfer: Bool) {
        self.isTransfer = isTransfer
        phase = isTransfer ? .transferDestination : .active
    }
}
