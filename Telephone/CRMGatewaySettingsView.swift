//
//  CRMGatewaySettingsView.swift
//  Telephone
//

import SwiftUI

struct CRMGatewaySettingsView: View {
    @Bindable var model: CRMGatewaySettingsModel

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
                LabeledContent(NSLocalizedString("Gateway address", comment: "CRM gateway origin label.")) {
                    TextField("https://gateway.example", text: $model.origin)
                        .accessibilityIdentifier("settings.crm.origin")
                }
                LabeledContent(NSLocalizedString("Gateway token", comment: "CRM gateway token label.")) {
                    SecureField("", text: $model.newToken)
                        .accessibilityIdentifier("settings.crm.token")
                }
                Text(NSLocalizedString(
                    "Use an HTTPS address without a path. The gateway token is stored in Keychain for this address; leave the field empty to keep it.",
                    comment: "CRM origin and token settings help."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(NSLocalizedString(
                    "CRM email and password stay on the gateway computer.",
                    comment: "CRM credentials location help."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                if model.settings.hasSavedToken {
                    HStack {
                        Label(NSLocalizedString("Gateway token saved", comment: "CRM token status."), systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(NSLocalizedString("Remove token", comment: "CRM token removal action.")) {
                            Task { await model.removeToken() }
                        }
                        .disabled(model.isSaving)
                    }
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
    }
}

extension CRMGatewayError {
    var crmMessage: String {
        switch self {
        case .disabled:
            NSLocalizedString("CRM lookup is disabled in Settings.", comment: "CRM disabled error.")
        case .invalidOrigin:
            NSLocalizedString("Enter a valid HTTPS gateway address without a path, query, or credentials.", comment: "CRM gateway origin error.")
        case .missingToken:
            NSLocalizedString("Save a gateway token for this address in CRM Settings.", comment: "CRM missing token error.")
        case .invalidKeyNumber:
            NSLocalizedString("Enter a positive numeric key number.", comment: "CRM key number validation.")
        case .invalidPhoneNumber:
            NSLocalizedString("The caller does not have a valid phone number for CRM lookup.", comment: "CRM phone validation failure.")
        case .invalidEmail:
            NSLocalizedString("Enter one valid email address.", comment: "CRM invalid email address.")
        case .forbidden:
            NSLocalizedString("This gateway token cannot link phone numbers. Ask the gateway operator to enable this permission.", comment: "CRM phone append permission failure.")
        case .conflict:
            NSLocalizedString("The organization’s phones changed. Refresh its details before linking the number.", comment: "CRM optimistic concurrency conflict.")
        case .phoneWriteUnconfirmed:
            NSLocalizedString("Couldn’t confirm the phone association. Refresh the organization before trying again.", comment: "CRM unknown phone write outcome.")
        case .unauthorized:
            NSLocalizedString("The gateway rejected the token. Update it in CRM Settings.", comment: "CRM authorization error.")
        case .unavailable:
            NSLocalizedString("The gateway or CRM is unavailable. Check the connection and try again.", comment: "CRM unavailable error.")
        case .rateLimited:
            NSLocalizedString("Too many requests. Try again shortly.", comment: "CRM rate limit error.")
        case .redirectDenied:
            NSLocalizedString("The gateway redirected the request. Check its address in CRM Settings.", comment: "CRM redirect refusal.")
        case .invalidResponse:
            NSLocalizedString("The gateway returned an incomplete or invalid response.", comment: "CRM contract failure.")
        case .keychain:
            NSLocalizedString("Couldn’t save or remove the gateway token in Keychain.", comment: "CRM Keychain failure.")
        }
    }
}
