//
//  AccountControllerToAccountAdapter.swift
//  Telephone
//
//  Adapts AccountController to the UseCases Account protocol.
//

import Foundation
import UseCases

final class AccountControllerToAccountAdapter:
    Account,
    @unchecked Sendable
{
    private weak var controller: AccountController?

    init(controller: AccountController) {
        self.controller = controller
    }

    var uuid: String {
        controller?.account.uuid ?? ""
    }

    var domain: String {
        controller?.account.domain ?? ""
    }

    func makeCall(to uri: URI, label: String) {
        guard let controller else { return }

        let destination = AKSIPURI(
            user: uri.user,
            host: uri.host,
            displayName: uri.displayName
        )
        controller.makeCall(
            to: destination,
            phoneLabel: label
        )
    }
}
