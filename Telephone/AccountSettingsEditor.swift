//
//  AccountSettingsEditor.swift
//  Telephone
//

import SwiftUI

struct AccountSettingsEditor: View {
    @Bindable var model: AccountSettingsModel

    var body: some View {
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
                    .disabled(editingIsDisabled)
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
                .disabled(editingIsDisabled)

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
                .disabled(editingIsDisabled)
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

    private var editingIsDisabled: Bool {
        model.draft.isEnabled
            || model.passwordIsLoading
            || model.credentialsAreSaving
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { model.draft.isEnabled },
            set: model.setEnabled
        )
    }

}
