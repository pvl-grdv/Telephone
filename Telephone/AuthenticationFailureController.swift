//
//  AuthenticationFailureController.swift
//  Telephone
//

import Foundation

private extension Notification.Name {
    static let authenticationFailureCredentialsDidChange =
        Notification.Name("AKAuthenticationFailureControllerDidChangeUsernameAndPassword")
}

@MainActor
@objcMembers
final class AuthenticationFailureController: NSObject {
    private(set) weak var accountController: AccountController?
    private let userAgent: AKSIPUserAgent

    @nonobjc
    init(
        accountController: AccountController,
        userAgent: AKSIPUserAgent
    ) {
        self.accountController = accountController
        self.userAgent = userAgent
        super.init()
    }

    @nonobjc
    func makeModel() -> AuthenticationFailureModel? {
        guard
            let accountController,
            let account = accountController.account
        else {
            return nil
        }

        let registrar = account.registrar.stringValue
        let username = account.username
        let service = "SIP: \(registrar)"

        return AuthenticationFailureModel(
            registrar: registrar,
            username: username,
            password: AKKeychain.password(
                forService: service,
                account: username
            ),
            savesPassword: true
        )
    }

    @nonobjc
    func changeUsernameAndPassword(_ model: AuthenticationFailureModel) {
        let username = model.username.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let password = model.password
        defer {
            model.password = ""
        }

        guard
            !username.isEmpty,
            let accountController,
            let account = accountController.account
        else {
            return
        }
        accountController.removeAccountFromUserAgent()
        account.updateUsername(username)

        accountController.showConnectingState()

        _ = userAgent.add(
            account,
            withPassword: password
        )

        if !accountController.isAccountRegistered
            && account.registrationExpireTime == kAKSIPAccountRegistrationExpireTimeNotSpecified
        {
            accountController.showUnavailableState()
            accountController.showRegistrarConnectionErrorSheetWithError(
                registrationError(for: account)
            )
        }

        if model.savesPassword {
            let service = "SIP: \(account.registrar.stringValue)"
            _ = AKKeychain.addItem(
                withService: service,
                account: username,
                password: password
            )
        }

        NotificationCenter.default.post(
            name: .authenticationFailureCredentialsDidChange,
            object: self
        )
    }

    private func registrationError(for account: AKSIPAccount) -> String {
        let status = account.registrationStatus
        let statusText: String?

        if Bundle.main.preferredLocalizations.first == "ru" {
            statusText = LocalizedStringForSIPResponseCode(status)
        } else {
            statusText = account.registrationStatusText
        }

        guard let statusText, !statusText.isEmpty else {
            return String(
                format: NSLocalizedString(
                    "Error %ld",
                    comment: "Error #."
                ),
                status
            ) + "."
        }

        return String(
            format: NSLocalizedString(
                "The error was: “%ld %@”.",
                comment: "Error description."
            ),
            status,
            statusText
        )
    }
}
