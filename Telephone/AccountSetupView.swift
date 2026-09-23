//
//  AccountSetupView.swift
//  Telephone
//

import AppKit
import Observation
import SwiftUI

let accountSetupDidAddNotificationName =
    Notification.Name("AKAccountSetupControllerDidAddAccount")

@MainActor
@Observable
final class AccountSetupModel {
    var fullName = ""
    var domain = ""
    var username = ""
    var password = ""

    var fullNameInvalid = false
    var domainInvalid = false
    var usernameInvalid = false
    var passwordInvalid = false

    func reset() {
        fullName = ""
        domain = ""
        username = ""
        password = ""
        fullNameInvalid = false
        domainInvalid = false
        usernameInvalid = false
        passwordInvalid = false
    }

    func saveAccount(notificationObject: AnyObject? = nil) -> Bool {
        guard let account = validatedAccount() else {
            return false
        }

        var accounts =
            UserDefaults.standard.array(forKey: UserDefaultsKeys.accounts)
            as? [[String: Any]] ?? []
        accounts.append(account)
        UserDefaults.standard.set(accounts, forKey: UserDefaultsKeys.accounts)

        let domain = account[AKSIPAccountKeys.domain] as? String ?? ""
        let username = account[AKSIPAccountKeys.username] as? String ?? ""
        _ = AKKeychain.addItem(
            withService: "SIP: \(domain)",
            account: username,
            password: password
        )

        NotificationCenter.default.post(
            name: accountSetupDidAddNotificationName,
            object: notificationObject ?? self,
            userInfo: account
        )
        return true
    }

    private func validatedAccount() -> [String: Any]? {
        let spaces = CharacterSet.whitespacesAndNewlines
        let normalizedFullName = fullName.trimmingCharacters(in: spaces)
        let normalizedDomain = domain.trimmingCharacters(in: spaces)
        let normalizedUsername = username.trimmingCharacters(in: spaces)

        fullNameInvalid = normalizedFullName.isEmpty
        domainInvalid = normalizedDomain.isEmpty
        usernameInvalid = normalizedUsername.isEmpty
        passwordInvalid = password.isEmpty

        guard
            !fullNameInvalid,
            !domainInvalid,
            !usernameInvalid,
            !passwordInvalid
        else {
            return nil
        }

        return [
            UserDefaultsKeys.accountEnabled: true,
            AKSIPAccountKeys.uuid: UUID().uuidString,
            AKSIPAccountKeys.fullName: normalizedFullName,
            AKSIPAccountKeys.domain: normalizedDomain,
            AKSIPAccountKeys.realm: "*",
            AKSIPAccountKeys.username: normalizedUsername,
            AKSIPAccountKeys.reregistrationTime: 0,
            UserDefaultsKeys.substitutePlusCharacter: false,
            UserDefaultsKeys.plusCharacterSubstitutionString: "00",
            AKSIPAccountKeys.useProxy: false,
            AKSIPAccountKeys.proxyHost: "",
            AKSIPAccountKeys.proxyPort: 0,
            AKSIPAccountKeys.transport: AKSIPAccountKeys.transportUDP,
            AKSIPAccountKeys.ipVersion: AKSIPAccountKeys.ipVersion4,
            AKSIPAccountKeys.updateContactHeader: true,
            AKSIPAccountKeys.updateViaHeader: true,
            AKSIPAccountKeys.updateSDP: true,
        ]
    }
}

struct AccountSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = AccountSetupModel()

    var body: some View {
        AccountSetupView(
            model: model,
            submit: submit,
            cancel: { dismiss() }
        )
        .onAppear {
            model.reset()
        }
    }

    private func submit() {
        guard model.saveAccount() else { return }
        dismiss()
    }
}

private enum AccountSetupField: Hashable {
    case fullName
    case domain
    case username
    case password
}

struct AccountSetupView: View {
    @Bindable var model: AccountSetupModel
    @FocusState private var focusedField: AccountSetupField?

    let submit: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .opacity(0.8)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        NSLocalizedString(
                            "SIP Account Setup",
                            comment: "Account setup title."
                        )
                    )
                    .font(.title2.weight(.semibold))

                    Text(
                        NSLocalizedString(
                            "Enter account details you received from your SIP provider.",
                            comment: "Account setup help text."
                        )
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Form {
                setupField(
                    NSLocalizedString(
                        "Full Name",
                        comment: "Account settings label."
                    ),
                    text: $model.fullName,
                    prompt: NSLocalizedString(
                        "John Smith",
                        comment: "Account setup full name placeholder."
                    ),
                    invalid: model.fullNameInvalid,
                    field: .fullName
                )

                setupField(
                    NSLocalizedString(
                        "Domain",
                        comment: "Account settings label."
                    ),
                    text: $model.domain,
                    prompt: "example.com",
                    invalid: model.domainInvalid,
                    field: .domain
                )

                setupField(
                    NSLocalizedString(
                        "User Name",
                        comment: "Account settings label."
                    ),
                    text: $model.username,
                    prompt: NSLocalizedString(
                        "john",
                        comment: "Account setup username placeholder."
                    ),
                    invalid: model.usernameInvalid,
                    field: .username
                )

                LabeledContent(
                    NSLocalizedString(
                        "Password",
                        comment: "Account settings label."
                    )
                ) {
                    HStack(spacing: 8) {
                        SecureField(
                            "",
                            text: $model.password,
                            prompt: Text(
                                NSLocalizedString(
                                    "Required",
                                    comment: "Required field placeholder."
                                )
                            )
                        )
                        .focused($focusedField, equals: .password)
                        .onSubmit(submit)

                        validationIcon(model.passwordInvalid)
                    }
                }
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
                        "Done",
                        comment: "Account setup confirmation button."
                    ),
                    action: submit
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(minWidth: 480, idealWidth: 520, maxWidth: 560)
        .defaultFocus($focusedField, .fullName)
    }

    private func setupField(
        _ title: String,
        text: Binding<String>,
        prompt: String,
        invalid: Bool,
        field: AccountSetupField
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField("", text: text, prompt: Text(prompt))
                    .focused($focusedField, equals: field)
                    .onSubmit {
                        advanceFocus(after: field)
                    }

                validationIcon(invalid)
            }
        }
    }

    private func advanceFocus(after field: AccountSetupField) {
        switch field {
        case .fullName:
            focusedField = .domain
        case .domain:
            focusedField = .username
        case .username:
            focusedField = .password
        case .password:
            submit()
        }
    }

    @ViewBuilder
    private func validationIcon(_ invalid: Bool) -> some View {
        if invalid {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .help(
                    NSLocalizedString(
                        "Required",
                        comment: "Required field placeholder."
                    )
                )
        } else {
            Color.clear
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
        }
    }
}
