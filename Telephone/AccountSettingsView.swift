//
//  AccountSettingsView.swift
//  Telephone
//

import Foundation
import SwiftUI

extension AccountSettingsModel {
    convenience init(preferencesController: AnyObject?) {
        self.init(
            preferencesController: preferencesController,
            credentials: CredentialsStore.shared
        )
    }
}

struct AccountSettingsView: View {
    @Bindable var model: AccountSettingsModel

    var body: some View {
        HStack(spacing: 0) {
            accountList
            Divider()
            editor
        }
        .alert(model.removalAlertTitle, isPresented: removalPresented) {
            Button(NSLocalizedString("Delete", comment: "Delete button."), role: .destructive) {
                model.confirmRemoval()
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel button."), role: .cancel) {
                model.cancelRemoval()
            }
        } message: {
            Text(model.removalAlertMessage)
        }
        .alert(
            NSLocalizedString(
                "Could not save account password.",
                comment: "Account credentials save error."
            ),
            isPresented: credentialsErrorPresented
        ) {
            Button(
                NSLocalizedString("OK", comment: "OK button."),
                role: .cancel
            ) {
                model.dismissCredentialsError()
            }
        }
    }

    private var accountList: some View {
        VStack(spacing: 0) {
            List(selection: $model.selection) {
                ForEach(model.accounts) { account in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(account.isEnabled ? Color.green : Color.secondary.opacity(0.45))
                            .frame(width: 7, height: 7)

                        Text(account.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .tag(account.id)
                }
                .onMove(perform: model.moveAccounts)
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 6) {
                Button {
                    model.addAccount()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(!model.canAddAccount)
                .help(NSLocalizedString("Add Account", comment: "Add account button."))

                Button {
                    model.requestRemoval()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(!model.hasSelection)
                .help(NSLocalizedString("Remove Account", comment: "Remove account button."))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .frame(width: 205)
    }

    @ViewBuilder
    private var editor: some View {
        if model.hasSelection {
            Form {
                Section(NSLocalizedString("Account Information", comment: "Account settings section.")) {
                    Toggle(
                        NSLocalizedString("Enable this account", comment: "Account settings toggle."),
                        isOn: enabled
                    )
                    .disabled(
                        model.credentialsAreSaving
                            || (!model.draft.isEnabled && model.passwordIsLoading)
                            || (!model.draft.isEnabled && model.proxyPortInvalid)
                    )

                    if model.draft.isEnabled {
                        Label(
                            NSLocalizedString(
                                "Disable account to change settings.",
                                comment: "Enabled account editing hint."
                            ),
                            systemImage: "lock"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Group {
                        LabeledContent(NSLocalizedString("Description", comment: "Account settings label.")) {
                            TextField(
                                "",
                                text: $model.draft.descriptionText,
                                prompt: Text(model.descriptionPlaceholder)
                            )
                        }
                        LabeledContent(NSLocalizedString("Full Name", comment: "Account settings label.")) {
                            TextField("", text: $model.draft.fullName)
                        }
                        LabeledContent(NSLocalizedString("Domain", comment: "Account settings label.")) {
                            TextField("", text: $model.draft.domain)
                        }
                        LabeledContent(NSLocalizedString("User Name", comment: "Account settings label.")) {
                            TextField("", text: $model.draft.username)
                        }
                        LabeledContent(NSLocalizedString("Password", comment: "Account settings label.")) {
                            SecureField("", text: $model.draft.password)
                        }
                    }
                    .disabled(
                        model.draft.isEnabled
                            || model.passwordIsLoading
                            || model.credentialsAreSaving
                    )
                }

                Section(NSLocalizedString("Network", comment: "Account settings section.")) {
                    Toggle(
                        NSLocalizedString("Connect using proxy", comment: "Account proxy toggle."),
                        isOn: $model.draft.usesProxy
                    )

                    LabeledContent(NSLocalizedString("Server", comment: "Account settings label.")) {
                        TextField("", text: $model.draft.proxyHost)
                    }
                    .disabled(!model.draft.usesProxy)

                    LabeledContent(NSLocalizedString("Port", comment: "Account settings label.")) {
                        TextField(
                            "",
                            text: $model.draft.proxyPort,
                            prompt: Text(model.proxyPortPlaceholder)
                        )
                        .frame(width: 120)
                    }
                    .disabled(!model.draft.usesProxy)

                    if model.proxyPortInvalid {
                        Label(
                            NSLocalizedString(
                                "Port must be between 1 and 65535, or left empty.",
                                comment: "Invalid SIP proxy port message."
                            ),
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    }

                    Picker(
                        NSLocalizedString("SIP Transport", comment: "Account settings label."),
                        selection: $model.draft.transport
                    ) {
                        Text("UDP").tag(AKSIPAccountKeys.transportUDP)
                        Text("TCP").tag(AKSIPAccountKeys.transportTCP)
                        Text("TLS").tag(AKSIPAccountKeys.transportTLS)
                    }
                    .pickerStyle(.segmented)

                    Picker(
                        NSLocalizedString("IP Version", comment: "Account settings label."),
                        selection: $model.draft.ipVersion
                    ) {
                        Text("IPv4").tag(AKSIPAccountKeys.ipVersion4)
                        Text("IPv6").tag(AKSIPAccountKeys.ipVersion6)
                    }
                    .pickerStyle(.segmented)

                    Picker(
                        NSLocalizedString("Update IP address", comment: "Account settings label."),
                        selection: $model.draft.ipUpdateMode
                    ) {
                        ForEach(AccountIPUpdateMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(
                        NSLocalizedString(
                            "Enabling this option may solve some audio problems.",
                            comment: "Account IP address update help text."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .disabled(
                        model.draft.isEnabled
                            || model.passwordIsLoading
                            || model.credentialsAreSaving
                    )

                Section(NSLocalizedString("Advanced", comment: "Account settings section.")) {
                    LabeledContent(NSLocalizedString("SIP Address", comment: "Account settings label.")) {
                        TextField(
                            "",
                            text: $model.draft.sipAddress,
                            prompt: Text(model.defaultSIPAddress)
                        )
                    }

                    LabeledContent(NSLocalizedString("Registry Server", comment: "Account settings label.")) {
                        TextField(
                            "",
                            text: $model.draft.registrar,
                            prompt: Text(model.draft.domain)
                        )
                    }

                    LabeledContent(NSLocalizedString("Reregister every", comment: "Account settings label.")) {
                        HStack(spacing: 6) {
                            TextField(
                                "",
                                text: $model.draft.reregistrationTime,
                                prompt: Text("300")
                            )
                            .frame(width: 90)
                            Text(NSLocalizedString("seconds", comment: "Account settings unit."))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Toggle(
                            NSLocalizedString("Replace “+” with", comment: "Account settings toggle."),
                            isOn: $model.draft.substitutesPlusCharacter
                        )

                        TextField("", text: $model.draft.plusCharacterSubstitution)
                            .frame(width: 100)
                            .disabled(!model.draft.substitutesPlusCharacter)
                    }
                }
                .disabled(
                        model.draft.isEnabled
                            || model.passwordIsLoading
                            || model.credentialsAreSaving
                    )
            }
            .formStyle(.grouped)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 6)
        } else {
            ContentUnavailableView {
                Label(
                    NSLocalizedString("No Account Selected", comment: "Empty account settings title."),
                    systemImage: "at"
                )
            } description: {
                Text(
                    NSLocalizedString(
                        "Select an account to edit its settings.",
                        comment: "Empty account settings description."
                    )
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { model.draft.isEnabled },
            set: model.setEnabled
        )
    }

    private var credentialsErrorPresented: Binding<Bool> {
        Binding(
            get: { model.showsCredentialsError },
            set: { isPresented in
                if !isPresented {
                    model.dismissCredentialsError()
                }
            }
        )
    }

    private var removalPresented: Binding<Bool> {
        Binding(
            get: { model.pendingRemovalID != nil },
            set: { isPresented in
                if !isPresented {
                    model.cancelRemoval()
                }
            }
        )
    }
}
