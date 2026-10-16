//
//  CRMGatewaySettingsView.swift
//  Telephone
//

import SwiftUI

struct CRMGatewaySettingsView: View {
    @Bindable var model: CRMGatewaySettingsModel
    @State private var isShowingReuseConfirmation = false

    var body: some View {
        Form {
            Section {
                Toggle(
                    NSLocalizedString("Enable CRM lookup", comment: "CRM settings toggle."),
                    isOn: $model.enabled
                )
                Text(NSLocalizedString(
                    "Find the organization by the caller’s phone number, with key number lookup as a fallback.",
                    comment: "CRM settings explanation."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("Gateway address", comment: "CRM gateway origin label."))
                    TextField(
                        NSLocalizedString("Gateway address", comment: "CRM gateway origin label."),
                        text: $model.origin,
                        prompt: Text(verbatim: "https://gateway.example")
                    )
                        .labelsHidden()
                        .accessibilityIdentifier("settings.crm.origin")
                }
                Toggle(
                    NSLocalizedString("Allow HTTP over Tailscale", comment: "CRM Tailscale HTTP opt-in."),
                    isOn: $model.allowTailscaleHTTP
                )
                .accessibilityIdentifier("settings.crm.allowTailscaleHTTP")
                if model.allowTailscaleHTTP {
                    Text(NSLocalizedString(
                        "For an address beginning with http://, keep Tailscale connected and include the gateway port. Use only the address supplied by your gateway operator.",
                        comment: "CRM Tailscale HTTP security explanation."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("Gateway token", comment: "CRM gateway token label."))
                    SecureField(
                        NSLocalizedString("Gateway token", comment: "CRM gateway token label."),
                        text: $model.newToken,
                        prompt: Text(NSLocalizedString("Paste the device token", comment: "CRM token field prompt."))
                    )
                        .labelsHidden()
                        .accessibilityIdentifier("settings.crm.token")
                }
                Text(NSLocalizedString(
                    "This token connects Telephone to the gateway. It is not your CRM password or a Tailscale login. Once saved for this address, it can be left blank.",
                    comment: "CRM origin and token settings help."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                if let savedOrigin = model.savedTokenOrigin {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            String(format: NSLocalizedString(
                                "Token saved for: %@", comment: "CRM token status showing its saved address."
                            ), savedOrigin),
                            systemImage: "lock.fill"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if model.canReuseSavedToken {
                            Text(NSLocalizedString(
                                "The address has changed. Enter its device token, or reuse the saved token only if both addresses belong to the same gateway.",
                                comment: "CRM changed address credential guidance."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Button(NSLocalizedString(
                                "Use saved token for this address", comment: "CRM explicit token reuse action."
                            )) {
                                isShowingReuseConfirmation = model.prepareTokenReuse()
                            }
                            .accessibilityIdentifier("settings.crm.reuseToken")
                        }
                        Button(NSLocalizedString("Remove saved token", comment: "CRM saved-origin token removal action.")) {
                            Task { await model.removeToken() }
                        }
                        .help(String(format: NSLocalizedString(
                            "Remove the token saved for %@", comment: "CRM token removal saved address help."
                        ), savedOrigin))
                        .disabled(model.isSaving)
                    }
                }
            }

            Section {
                CRMGatewayStatusView(model: model)
            }

            Section {
                DisclosureGroup(NSLocalizedString(
                    "How to connect to the gateway", comment: "CRM gateway setup help disclosure."
                )) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString(
                            "1. On the gateway computer, open the gateway setup shortcut and sign in to CRM once. The gateway keeps the CRM session active automatically.",
                            comment: "CRM gateway local login setup instruction."
                        ))
                        Text(NSLocalizedString(
                            "2. In that local setup page, create a device token for this Mac and copy it. Ask the gateway operator if you do not have access.",
                            comment: "CRM gateway device token setup instruction."
                        ))
                        Text(NSLocalizedString(
                            "3. Enter the gateway address and device token here, enable CRM lookup, and select Apply. Tailscale Serve provides network access; it does not sign you in to the gateway.",
                            comment: "CRM gateway Telephone connection setup instruction."
                        ))
                        Text(NSLocalizedString(
                            "CRM email and password stay on the gateway computer.",
                            comment: "CRM credentials location help."
                        ))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                }
            }

            Section {
                if let error = model.error {
                    Label(error.crmMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if model.saved {
                    Label(NSLocalizedString("CRM settings saved", comment: "CRM settings success."), systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if model.isSaving { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(NSLocalizedString("Revert", comment: "Revert CRM settings.")) { model.discard() }
                        .disabled(model.isSaving || !model.hasChanges)
                    Button(NSLocalizedString("Apply", comment: "Apply CRM settings.")) {
                        Task { await model.save() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isSaving || !model.hasChanges)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.isSaving)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityIdentifier("settings.crm.content")
        .task { await model.settings.refreshTokenPresence() }
        .confirmationDialog(
            NSLocalizedString("Use the saved token for another address?", comment: "CRM token reuse confirmation title."),
            isPresented: $isShowingReuseConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Use saved token and apply", comment: "CRM token reuse confirmation action.")) {
                Task { await model.reuseSavedToken() }
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel CRM token reuse."), role: .cancel) {
                model.cancelTokenReuse()
            }
        } message: {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: NSLocalizedString(
                    "Saved address: %@", comment: "CRM token reuse saved address."
                ), model.tokenReuseSource))
                Text(String(format: NSLocalizedString(
                    "New address: %@", comment: "CRM token reuse destination address."
                ), model.tokenReuseDestination))
                Text(NSLocalizedString(
                    "Confirm only if both addresses lead to the same gateway. The token will be saved for the new address and these settings will be applied.",
                    comment: "CRM token reuse confirmation explanation."
                ))
            }
        }
    }


}
