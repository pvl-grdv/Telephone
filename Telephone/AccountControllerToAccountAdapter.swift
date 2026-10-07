//
//  AccountControllerToAccountAdapter.swift
//  Telephone
//
//  Adapts AccountController to the UseCases Account protocol.
//

import Foundation
import UseCases

final class AccountControllerToAccountAdapter:
    CallMakingAccount,
    Sendable
{
    @MainActor private weak var controller: AccountController?

    let uuid: String
    let domain: String

    @MainActor
    init(controller: AccountController) {
        self.controller = controller
        uuid = controller.account.uuid
        domain = controller.account.domain
    }

    @MainActor
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
