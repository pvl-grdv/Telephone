//
//  ActiveAccountTransferViewController.swift
//  Telephone
//

import AppKit
import SwiftUI

@MainActor
@objcMembers
final class ActiveAccountTransferViewController: ActiveAccountViewController {
    @objc(initWithAccountController:)
    override init(accountController: AccountController) {
        super.init(accountController: accountController)

        callDestinationField.isHidden = false
        callDestinationField.target = self
        callDestinationField.action = #selector(makeCallToTransferDestination(_:))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSHostingView(
            rootView: ActiveAccountTransferView(
                field: callDestinationField,
                call: { [weak self] in
                    self?.makeCallToTransferDestination(nil)
                },
                close: { [weak self] in
                    self?.closeTransferSheet()
                }
            )
        )
    }

    override func makeCall(_ sender: Any?) {
        // The transfer sheet makes the destination call explicitly.
    }

    @IBAction func makeCallToTransferDestination(_ sender: Any?) {
        guard
            let uri = callDestinationURI,
            let controller = accountController,
            let transferController = view.window?.windowController as? CallTransferController
        else {
            return
        }

        controller.makeCall(
            to: uri,
            phoneLabel: callDestinationPhoneLabel,
            callTransferController: transferController
        )
    }

    private func closeTransferSheet() {
        guard let transferController = view.window?.windowController as? CallTransferController else {
            return
        }
        transferController.closeSheet(self)
    }
}

private struct ActiveAccountTransferView: View {
    let field: NSTokenField
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

            TokenFieldView(field: field)
                .frame(height: 24)

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
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 320, idealWidth: 320, minHeight: 118, idealHeight: 118)
    }
}
