//
//  AuthenticationFailureController.swift
//  Telephone
//

import AppKit
import SwiftUI

private extension Notification.Name {
    static let authenticationFailureCredentialsDidChange =
        Notification.Name("AKAuthenticationFailureControllerDidChangeUsernameAndPassword")
}

@MainActor
@objcMembers
final class AuthenticationFailureController: NSWindowController {
    private(set) weak var accountController: AccountController?
    private let userAgent: AKSIPUserAgent
    private let model = AuthenticationFailureModel()

    @objc(initWithAccountController:userAgent:)
    init(
        accountController: AccountController,
        userAgent: AKSIPUserAgent
    ) {
        self.accountController = accountController
        self.userAgent = userAgent
        super.init(window: nil)

        let contentController = NSHostingController(
            rootView: AuthenticationFailureView(
                model: model,
                cancel: { [weak self] in
                    self?.closeSheet(nil)
                },
                submit: { [weak self] in
                    self?.changeUsernameAndPassword(nil)
                }
            )
        )

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString(
            "Authentication Failure",
            comment: "Authentication failure window title."
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = contentController
        window.setContentSize(contentController.view.fittingSize)
        self.window = window
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc(presentFromParentWindow:)
    func present(from parent: NSWindow) {
        prepareForPresentation()
        guard let window else { return }
        parent.beginSheet(window)
    }

    private func prepareForPresentation() {
        guard
            let accountController,
            let account = accountController.account
        else {
            return
        }

        let registrar = account.registrar.stringValue
        let username = account.username
        let service = "SIP: \(registrar)"

        model.registrar = registrar
        model.username = username
        model.password = AKKeychain.password(
            forService: service,
            account: username
        )
        model.savesPassword = true
        model.focusRequest &+= 1
    }

    @IBAction func closeSheet(_ sender: Any?) {
        guard
            let window,
            let parent = window.sheetParent
        else {
            return
        }
        parent.endSheet(window)
    }

    @IBAction func changeUsernameAndPassword(_ sender: Any?) {
        closeSheet(sender)

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
