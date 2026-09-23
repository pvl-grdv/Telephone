//
//  CallTransferCoordinator.swift
//  Telephone
//

import Foundation

@MainActor
final class CallTransferCoordinator {
    private weak var callController: CallController?
    private let model: CallWindowModel

    let destinationComposer: CallDestinationComposer?

    private var waitingForHold = false

    init(
        callController: CallController,
        accountController: AccountController,
        model: CallWindowModel
    ) {
        self.callController = callController
        self.model = model
        destinationComposer = model.isTransfer
            ? CallDestinationComposer(accountController: accountController)
            : nil
    }

    func resetForCallChange() {
        waitingForHold = false
    }

    func showDestinationState() {
        guard model.isTransfer else { return }

        waitingForHold = false
        model.phase = .transferDestination
        model.transferActionEnabled = false
        destinationComposer?.focus()
    }

    func setActionEnabled(_ enabled: Bool) {
        model.transferActionEnabled = enabled
    }

    func setCancelEnabled(_ enabled: Bool) {
        model.transferCancelEnabled = enabled
    }

    func focusDestination() {
        destinationComposer?.focus()
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

    func showSheet() {
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
            let presentation = CallPresentationRegistry.shared.presentation(
                for: transferController.identifier
            )
        else {
            return
        }

        presentation.showTransferDestinationState()
        model.transferPresentation = presentation
    }

    func callDestination() {
        guard
            let destinationComposer,
            let transferController = callController as? CallTransferController
        else {
            return
        }

        destinationComposer.makeCall(
            callTransferController: transferController
        )
    }

    func complete() {
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
            waitingForHold = true
        }
    }

    func closeSheet() {
        guard
            let transferController = callController as? CallTransferController
        else {
            return
        }

        transferController.closeSheet(nil)
    }

    func cancel() {
        guard
            let transferController = callController as? CallTransferController
        else {
            return
        }

        transferController.showInitialState(nil)
    }
}
