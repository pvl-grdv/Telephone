//
//  CallTransferController.swift
//  Telephone
//
//  Small specialization of CallController for an attended transfer.
//

import Foundation

@MainActor
@objc(CallTransferController)
@objcMembers
final class CallTransferController: CallController {
    private weak var sourceCallController: CallController?

    @objc(initWithSourceCallController:userAgent:)
    init(
        sourceCallController: CallController,
        userAgent: AKSIPUserAgent
    ) {
        self.sourceCallController = sourceCallController

        super.init(
            windowNibName: "CallTransfer",
            accountController: sourceCallController.accountController,
            userAgent: userAgent,
            delegate: sourceCallController.accountController
        )

        showInitialState(nil)
    }

    override var callTransferController: CallTransferController? {
        nil
    }

    func transferCall() {
        guard
            let sourceCall = sourceCallController?.call,
            let destinationCall = call
        else {
            return
        }

        sourceCall.attendedTransfer(to: destinationCall)
    }

    @objc(closeSheet:)
    func closeSheet(_ sender: Any?) {
        guard let sourceCallController else { return }

        if sourceCallController.callActive,
           sourceCallController.callOnHold
        {
            sourceCallController.toggleCallHold()
        }

        sourceCallController.dismissCallTransfer()
        sourceCallController.discardCallTransfer()
    }

    @objc(showInitialState:)
    func showInitialState(_ sender: Any?) {
        if callActive {
            hangUpCall()
        }

        guard sourceCallController?.callActive == true else {
            closeSheet(nil)
            return
        }

        showTransferDestinationState()
        focusTransferDestination()
    }

    override func acceptCall() {
        // Transfer destination calls are outgoing only.
    }

    override func prepareForCall() {
        super.prepareForCall()
        setTransferActionEnabled(false)
    }

    override func sipCallEarly(_ notification: Notification) {
        super.sipCallEarly(notification)
        setTransferActionEnabled(false)
    }

    override func sipCallDidLocalHold(_ notification: Notification) {
        super.sipCallDidLocalHold(notification)
        callDidHoldForTransfer()
    }
}
