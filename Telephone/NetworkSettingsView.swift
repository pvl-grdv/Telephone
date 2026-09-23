//
//  NetworkSettingsView.swift
//  Telephone
//

import Cocoa
import Observation
import SwiftUI

@MainActor
@Observable
final class NetworkSettingsModel: NSObject {
    var transportPort = ""
    var stunServerHost = ""
    var stunServerPort = ""
    var usesICE = false
    var usesDNSSRV = false
    var outboundProxyHost = ""
    var outboundProxyPort = ""
    var transportPortPlaceholder = ""

    private let defaults = UserDefaults.standard
    private let userAgent: AKSIPUserAgent
    private weak var preferencesController: PreferencesController?

    init(userAgent: AKSIPUserAgent, preferencesController: PreferencesController) {
        self.userAgent = userAgent
        self.preferencesController = preferencesController
        super.init()
        discard()
        refreshTransportPortPlaceholder()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userAgentDidFinishStarting),
            name: NSNotification.Name.AKSIPUserAgentDidFinishStarting,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var hasChanges: Bool {
        normalizedPort(transportPort) != defaults.integer(forKey: UserDefaultsKeys.transportPort)
            || normalizedHost(stunServerHost) != (defaults.string(forKey: UserDefaultsKeys.stunServerHost) ?? "")
            || normalizedPort(stunServerPort) != defaults.integer(forKey: UserDefaultsKeys.stunServerPort)
            || usesICE != defaults.bool(forKey: UserDefaultsKeys.useICE)
            || usesDNSSRV != defaults.bool(forKey: UserDefaultsKeys.useDNSSRV)
            || normalizedHost(outboundProxyHost) != (defaults.string(forKey: UserDefaultsKeys.outboundProxyHost) ?? "")
            || normalizedPort(outboundProxyPort) != defaults.integer(forKey: UserDefaultsKeys.outboundProxyPort)
    }

    func save() {
        defaults.set(normalizedPort(transportPort), forKey: UserDefaultsKeys.transportPort)
        defaults.set(normalizedHost(stunServerHost), forKey: UserDefaultsKeys.stunServerHost)
        defaults.set(normalizedPort(stunServerPort), forKey: UserDefaultsKeys.stunServerPort)
        defaults.set(usesICE, forKey: UserDefaultsKeys.useICE)
        defaults.set(usesDNSSRV, forKey: UserDefaultsKeys.useDNSSRV)
        defaults.set(normalizedHost(outboundProxyHost), forKey: UserDefaultsKeys.outboundProxyHost)
        defaults.set(normalizedPort(outboundProxyPort), forKey: UserDefaultsKeys.outboundProxyPort)

        NotificationCenter.default.post(
            name: .AKPreferencesControllerDidChangeNetworkSettings,
            object: preferencesController
        )
        refreshTransportPortPlaceholder()
    }

    func discard() {
        transportPort = stringValue(for: UserDefaultsKeys.transportPort)
        stunServerHost = defaults.string(forKey: UserDefaultsKeys.stunServerHost) ?? ""
        stunServerPort = stringValue(for: UserDefaultsKeys.stunServerPort)
        usesICE = defaults.bool(forKey: UserDefaultsKeys.useICE)
        usesDNSSRV = defaults.bool(forKey: UserDefaultsKeys.useDNSSRV)
        outboundProxyHost = defaults.string(forKey: UserDefaultsKeys.outboundProxyHost) ?? ""
        outboundProxyPort = stringValue(for: UserDefaultsKeys.outboundProxyPort)
    }

    func clearOutboundProxy() {
        outboundProxyHost = ""
        outboundProxyPort = ""
    }

    func refreshTransportPortPlaceholder() {
        if userAgent.isStarted && userAgent.transportPort > 0 {
            transportPortPlaceholder = String(userAgent.transportPort)
        } else {
            transportPortPlaceholder = ""
        }
    }

    @objc private func userAgentDidFinishStarting(_ notification: Notification) {
        refreshTransportPortPlaceholder()
    }

    private func stringValue(for key: String) -> String {
        let value = defaults.integer(forKey: key)
        return value > 0 ? String(value) : ""
    }

    private func normalizedPort(_ value: String) -> Int {
        Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func normalizedHost(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

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
                    .disabled(!model.hasChanges)
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
        .padding()
        .onAppear { model.refreshTransportPortPlaceholder() }
    }
}
