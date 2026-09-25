//
//  NetworkSettingsView.swift
//  Telephone
//

import SwiftUI

struct NetworkSettingsView: View {
    @Bindable var model: NetworkSettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    NSLocalizedString("Local SIP Port", comment: "Network settings label.")
                ) {
                    TextField(model.transportPortPlaceholder, text: $model.transportPort)
                        .frame(width: 110)
                }

                Text(
                    NSLocalizedString(
                        "Leave empty to use any available port.",
                        comment: "Network settings help text."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if model.transportPortInvalid {
                    PortValidationMessage()
                }
            }

            Section {
                LabeledContent(
                    NSLocalizedString("STUN Server", comment: "Network settings label.")
                ) {
                    HStack {
                        TextField("", text: $model.stunServerHost)
                        TextField("3478", text: $model.stunServerPort)
                            .frame(width: 90)
                    }
                }

                if model.stunServerPortInvalid {
                    PortValidationMessage()
                }

                Toggle(
                    NSLocalizedString("Use ICE", comment: "Network settings toggle."),
                    isOn: $model.usesICE
                )

                Toggle(
                    NSLocalizedString("Use DNS SRV", comment: "Network settings toggle."),
                    isOn: $model.usesDNSSRV
                )
            }

            Section {
                LabeledContent(
                    NSLocalizedString("Outbound Proxy", comment: "Network settings label.")
                ) {
                    HStack {
                        TextField("", text: $model.outboundProxyHost)
                        TextField(
                            NSLocalizedString("Port", comment: "Network settings port field."),
                            text: $model.outboundProxyPort
                        )
                        .frame(width: 90)

                        if !model.outboundProxyHost.isEmpty || !model.outboundProxyPort.isEmpty {
                            Button {
                                model.clearOutboundProxy()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help(
                                NSLocalizedString(
                                    "Clear Outbound Proxy",
                                    comment: "Clear outbound proxy button."
                                )
                            )
                        }
                    }
                }

                Text(
                    NSLocalizedString(
                        "Use the account proxy instead.",
                        comment: "Network settings help text."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if model.outboundProxyPortInvalid {
                    PortValidationMessage()
                }
            }

            Section {
                HStack {
                    Spacer()

                    Button(
                        NSLocalizedString(
                            "Revert",
                            comment: "Revert network settings button."
                        )
                    ) {
                        model.discard()
                    }
                    .disabled(!model.hasChanges)

                    Button(
                        NSLocalizedString(
                            "Apply",
                            comment: "Apply network settings button."
                        )
                    ) {
                        model.save()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canApply)
                }

                Text(
                    NSLocalizedString(
                        "Applying network settings reconnects all accounts.",
                        comment: "Network settings apply help text."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.network.content")
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { model.refreshTransportPortPlaceholder() }
    }
}


private struct PortValidationMessage: View {
    var body: some View {
        Label(
            NSLocalizedString(
                "Port must be between 1 and 65535, or left empty.",
                comment: "Invalid SIP network port message."
            ),
            systemImage: "exclamationmark.circle"
        )
        .font(.caption)
        .foregroundStyle(.red)
    }
}
