//
//  AuthenticationFailureView.swift
//  Telephone
//

import Observation
import SwiftUI

@MainActor
@Observable
final class AuthenticationFailureModel {
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

struct AuthenticationFailureView: View {
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
        .frame(minWidth: 420, idealWidth: 454, maxWidth: 520)
        .defaultFocus($focusedField, .password)
        .onChange(of: model.focusRequest) {
            focusedField = .password
        }
    }
}
