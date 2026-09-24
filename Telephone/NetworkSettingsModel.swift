//
//  NetworkSettingsView.swift
//  Telephone
//

import Cocoa
import Observation

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

    private let defaults: UserDefaults
    private let userAgent: AKSIPUserAgent
    private weak var preferencesController: AnyObject?

    init(
        userAgent: AKSIPUserAgent,
        preferencesController: AnyObject,
        defaults: UserDefaults = .standard
    ) {
        self.userAgent = userAgent
        self.preferencesController = preferencesController
        self.defaults = defaults
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

    var transportPortInvalid: Bool {
        !SIPPortValidation.isValid(transportPort)
    }

    var stunServerPortInvalid: Bool {
        !SIPPortValidation.isValid(stunServerPort)
    }

    var outboundProxyPortInvalid: Bool {
        !SIPPortValidation.isValid(outboundProxyPort)
    }

    var hasInvalidPorts: Bool {
        transportPortInvalid
            || stunServerPortInvalid
            || outboundProxyPortInvalid
    }

    var hasChanges: Bool {
        comparablePort(transportPort)
                != defaults.integer(forKey: UserDefaultsKeys.transportPort)
            || normalizedHost(stunServerHost)
                != (defaults.string(
                    forKey: UserDefaultsKeys.stunServerHost
                ) ?? "")
            || comparablePort(stunServerPort)
                != defaults.integer(forKey: UserDefaultsKeys.stunServerPort)
            || usesICE != defaults.bool(forKey: UserDefaultsKeys.useICE)
            || usesDNSSRV != defaults.bool(
                forKey: UserDefaultsKeys.useDNSSRV
            )
            || normalizedHost(outboundProxyHost)
                != (defaults.string(
                    forKey: UserDefaultsKeys.outboundProxyHost
                ) ?? "")
            || comparablePort(outboundProxyPort)
                != defaults.integer(
                    forKey: UserDefaultsKeys.outboundProxyPort
                )
    }

    var canApply: Bool {
        hasChanges && !hasInvalidPorts
    }

    func save() {
        guard
            let transportPort = SIPPortValidation.value(transportPort),
            let stunServerPort = SIPPortValidation.value(stunServerPort),
            let outboundProxyPort = SIPPortValidation.value(
                outboundProxyPort
            )
        else {
            return
        }

        defaults.set(
            transportPort,
            forKey: UserDefaultsKeys.transportPort
        )
        defaults.set(
            normalizedHost(stunServerHost),
            forKey: UserDefaultsKeys.stunServerHost
        )
        defaults.set(
            stunServerPort,
            forKey: UserDefaultsKeys.stunServerPort
        )
        defaults.set(usesICE, forKey: UserDefaultsKeys.useICE)
        defaults.set(usesDNSSRV, forKey: UserDefaultsKeys.useDNSSRV)
        defaults.set(
            normalizedHost(outboundProxyHost),
            forKey: UserDefaultsKeys.outboundProxyHost
        )
        defaults.set(
            outboundProxyPort,
            forKey: UserDefaultsKeys.outboundProxyPort
        )

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

    private func comparablePort(_ value: String) -> Int {
        SIPPortValidation.value(value) ?? -1
    }

    private func normalizedHost(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

