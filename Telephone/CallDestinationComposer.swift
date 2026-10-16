//
//  CallDestinationComposer.swift
//  Telephone
//

import Foundation
import SwiftUI

@MainActor
final class CallDestinationComposer {
    private weak var accountController: AccountController?
    private let inputModel = CallDestinationInputModel()

    var callDestinationURI: AKSIPURI? {
        inputModel.callDestinationURI
    }

    var callDestinationPhoneLabel: String {
        inputModel.callDestinationPhoneLabel
    }

    var contentView: some View {
        inputView(
            showsCallButton: true,
            call: { [weak self] in
                self?.makeCall()
            }
        )
    }

    init(accountController: AccountController) {
        self.accountController = accountController
    }

    func makeCall(callTransferController: CallTransferController? = nil) {
        guard let uri = callDestinationURI else { return }

        if let callTransferController {
            accountController?.makeCall(
                to: uri,
                phoneLabel: callDestinationPhoneLabel,
                callTransferController: callTransferController
            )
        } else {
            accountController?.makeCall(
                to: uri,
                phoneLabel: callDestinationPhoneLabel
            )
        }
    }

    func makeCallToDestination(_ destination: String) {
        inputModel.setDestination(destination)
        makeCall()
    }

    func focus() {
        inputModel.requestFocus()
    }

    func inputView(
        showsCallButton: Bool,
        call: @escaping () -> Void
    ) -> some View {
        CallDestinationInputView(
            model: inputModel,
            showsCallButton: showsCallButton,
            call: call
        )
    }
}

struct TransferDestinationView: View {
    let composer: CallDestinationComposer
    let call: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                NSLocalizedString(
                    "Transfer to:",
                    comment: "Call transfer destination label."
                )
            )
            .font(.headline)

            composer.inputView(
                showsCallButton: false,
                call: call
            )

            HStack {
                Spacer()

                Button(
                    NSLocalizedString("Close", comment: "Close button."),
                    action: close
                )
                .keyboardShortcut(.cancelAction)

                Button(
                    NSLocalizedString("Call", comment: "Call button."),
                    action: call
                )
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        // Keep the native transfer sheet compact even for long contact names.
        .frame(width: 400)
        .frame(minHeight: 118)
    }
}
