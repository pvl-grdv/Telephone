//
//  AuthenticationFailureController.swift
//  Telephone
//

import AppKit
import Observation
import SwiftUI

private extension Notification.Name {
    static let authenticationFailureCredentialsDidChange =
        Notification.Name("AKAuthenticationFailureControllerDidChangeUsernameAndPassword")
}

@MainActor
@Observable
private final class AuthenticationFailureModel {
    var registrar = ""
    var username = ""
    var password = ""
    var savesPassword = true
    var focusRequest = 0

    var informativeText: String {
        String(
            format: NSLocalizedString(
                "Telephone was unable to login to %@. Change user name or password and try again.",
                comment: "Registrar authentication failed."
            ),
            registrar
        )
    }
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
            contentRect: NSRect(x: 0, y: 0, width: 454, height: 226),
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
        self.window = window
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForPresentation() {
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

private struct AuthenticationFailureView: View {
    @Bindable var model: AuthenticationFailureModel
    @FocusState private var focusedField: Field?

    let cancel: () -> Void
    let submit: () -> Void

    private enum Field: Hashable {
        case username
        case password
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        NSLocalizedString(
                            "Login failed.",
                            comment: "Authentication failure title."
                        )
                    )
                    .font(.headline)

                    Text(model.informativeText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }

            Form {
                LabeledContent(
                    NSLocalizedString(
                        "User Name",
                        comment: "Account settings label."
                    )
                ) {
                    TextField("", text: $model.username)
                        .focused($focusedField, equals: .username)
                }

                LabeledContent(
                    NSLocalizedString(
                        "Password",
                        comment: "Account settings label."
                    )
                ) {
                    SecureField("", text: $model.password)
                        .focused($focusedField, equals: .password)
                }

                Toggle(
                    NSLocalizedString(
                        "Remember this password in my Keychain",
                        comment: "Authentication failure Keychain toggle."
                    ),
                    isOn: $model.savesPassword
                )
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button(
                    NSLocalizedString("Cancel", comment: "Cancel button."),
                    action: cancel
                )
                .keyboardShortcut(.cancelAction)

                Button(
                    NSLocalizedString(
                        "Log In",
                        comment: "Authentication failure submit button."
                    ),
                    action: submit
                )
                .keyboardShortcut(.defaultAction)
                .disabled(
                    model.username
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }
        }
        .padding(20)
        .frame(width: 454)
        .defaultFocus($focusedField, .password)
        .onChange(of: model.focusRequest) {
            focusedField = .password
        }
    }
}
