//
//  CRMGatewayStatusView.swift
//  Telephone
//
//  Read-only gateway runtime and connection status.
//

import SwiftUI

struct CRMGatewayStatusView: View {
    let model: CRMGatewaySettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(NSLocalizedString("Running gateway", comment: "Runtime gateway identity heading."))
                Spacer()
                if model.isCheckingGateway { ProgressView().controlSize(.small) }
                Button(NSLocalizedString("Check connection", comment: "Authenticated gateway-only status request.")) {
                    Task { await model.checkConnection() }
                }
                .disabled(!model.canCheckConnection)
                .accessibilityIdentifier("settings.crm.checkConnection")
            }
            if model.hasChanges {
                Text(NSLocalizedString("Apply settings before checking the connection.", comment: "Status always checks saved configuration."))
                    .foregroundStyle(.secondary)
            } else if model.isCheckingGateway {
                Text(NSLocalizedString("Checking gateway…", comment: "Gateway status request in progress."))
                    .foregroundStyle(.secondary)
            } else if model.hasCurrentGatewayStatus {
                if let runtime = model.gatewayRuntime {
                    Label(NSLocalizedString("Gateway connected", comment: "Device token and gateway reachability confirmed."), systemImage: "checkmark.circle")
                    if let version = runtime.build.version {
                        LabeledContent(NSLocalizedString("Gateway version", comment: "Running version."), value: version)
                        if let commit = runtime.build.commit {
                            LabeledContent("Commit", value: commit).textSelection(.enabled)
                        }
                        if let value = runtime.build.builtAt, let date = CRMGatewayRuntime.date(value) {
                            LabeledContent(NSLocalizedString("Built", comment: "Build stamp packaging time."), value: date.formatted())
                        }
                    } else {
                        Text(NSLocalizedString("Gateway version unknown", comment: "Runtime reports unknown integrity."))
                    }
                    if let date = CRMGatewayRuntime.date(runtime.startedAt) {
                        LabeledContent(NSLocalizedString("Started", comment: "Running gateway process start time."), value: date.formatted())
                    }
                } else if let error = model.gatewayStatusError {
                    Label(error.crmMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                }
                if let date = model.gatewayCheckedAt {
                    Text(String(format: NSLocalizedString("Checked: %@", comment: "Gateway status check time."), date.formatted()))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(NSLocalizedString("Gateway version unknown", comment: "No runtime status yet."))
                    .foregroundStyle(.secondary)
            }
            Text(NSLocalizedString("Checks the gateway and device token without contacting CRM.", comment: "Status request scope, no CRM session claim."))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .accessibilityIdentifier("settings.crm.gatewayStatus")
    }
}
