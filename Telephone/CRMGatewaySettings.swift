//
//  CRMGatewaySettings.swift
//  Telephone
//

import Foundation
import Observation

protocol CRMGatewayTokenStoring: Sendable {
    func token(for origin: String) async -> String
    func save(_ token: String, for origin: String) async -> Bool
    func remove(for origin: String) async -> Bool
}

actor CRMGatewayKeychainTokenStore: CRMGatewayTokenStoring {
    private let service = "com.tlphn.Telephone.crm-gateway"

    func token(for origin: String) -> String {
        AKKeychain.password(forService: service, account: origin)
    }

    func save(_ token: String, for origin: String) -> Bool {
        AKKeychain.addItem(withService: service, account: origin, password: token)
    }

    func remove(for origin: String) -> Bool {
        AKKeychain.removeItem(forService: service, account: origin)
    }
}

@MainActor
@Observable
final class CRMGatewaySettings {
    private(set) var enabled: Bool
    private(set) var origin: String
    private(set) var allowTailscaleHTTP: Bool
    private(set) var generation = 0
    private(set) var hasSavedToken = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let tokenStore: any CRMGatewayTokenStoring
    private static let enabledKey = "Telephone.CRMGateway.enabled"
    private static let originKey = "Telephone.CRMGateway.origin"
    private static let allowTailscaleHTTPKey = "Telephone.CRMGateway.allowTailscaleHTTP"

    init(
        defaults: UserDefaults = .standard,
        tokenStore: any CRMGatewayTokenStoring = CRMGatewayKeychainTokenStore()
    ) {
        self.defaults = defaults
        self.tokenStore = tokenStore
        enabled = defaults.bool(forKey: Self.enabledKey)
        origin = defaults.string(forKey: Self.originKey) ?? ""
        allowTailscaleHTTP = defaults.bool(forKey: Self.allowTailscaleHTTPKey)
    }

    func refreshTokenPresence() async {
        let currentOrigin = origin
        let currentGeneration = generation
        let token = await tokenStore.token(for: currentOrigin)
        guard generation == currentGeneration, origin == currentOrigin else { return }
        hasSavedToken = !token.isEmpty
    }

    func configuration() async throws -> CRMGatewayConfiguration {
        guard enabled else { throw CRMGatewayError.disabled }
        let currentGeneration = generation
        let currentAllowed = allowTailscaleHTTP
        let currentOrigin = try CRMGatewayConfiguration.canonicalOrigin(
            origin, allowTailscaleHTTP: currentAllowed
        ).absoluteString
        let token = await tokenStore.token(for: currentOrigin)
        guard generation == currentGeneration, enabled else { throw CRMGatewayError.disabled }
        return try CRMGatewayConfiguration(
            origin: currentOrigin, token: token, allowTailscaleHTTP: currentAllowed
        )
    }

    func save(
        enabled: Bool, origin: String, newToken: String, allowTailscaleHTTP: Bool = false
    ) async throws {
        let currentGeneration = generation
        let inputOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalOrigin: String
        if inputOrigin.isEmpty && !enabled && newToken.isEmpty {
            canonicalOrigin = ""
        } else {
            canonicalOrigin = try CRMGatewayConfiguration.canonicalOrigin(
                inputOrigin, allowTailscaleHTTP: allowTailscaleHTTP
            ).absoluteString
        }
        var savedToken = ""
        if !newToken.isEmpty {
            _ = try CRMGatewayConfiguration(
                origin: canonicalOrigin, token: newToken, allowTailscaleHTTP: allowTailscaleHTTP
            )
            guard await tokenStore.save(newToken, for: canonicalOrigin) else {
                throw CRMGatewayError.keychain
            }
            savedToken = newToken
        } else if !canonicalOrigin.isEmpty {
            savedToken = await tokenStore.token(for: canonicalOrigin)
        }
        if enabled {
            _ = try CRMGatewayConfiguration(
                origin: canonicalOrigin, token: savedToken, allowTailscaleHTTP: allowTailscaleHTTP
            )
        }
        guard generation == currentGeneration else { throw CRMGatewayError.disabled }
        self.enabled = enabled
        self.origin = canonicalOrigin
        self.allowTailscaleHTTP = allowTailscaleHTTP
        hasSavedToken = !savedToken.isEmpty
        defaults.set(enabled, forKey: Self.enabledKey)
        defaults.set(canonicalOrigin, forKey: Self.originKey)
        defaults.set(allowTailscaleHTTP, forKey: Self.allowTailscaleHTTPKey)
        generation &+= 1
    }

    func tokenForConfirmedReuse(from source: String, generation expectedGeneration: Int) async throws -> String {
        guard generation == expectedGeneration, origin == source else { throw CRMGatewayError.disabled }
        let token = await tokenStore.token(for: source)
        guard generation == expectedGeneration, origin == source else { throw CRMGatewayError.disabled }
        guard !token.isEmpty else { throw CRMGatewayError.missingToken }
        return token
    }

    func removeToken() async throws {
        let currentOrigin = origin
        guard await tokenStore.remove(for: currentOrigin) else {
            throw CRMGatewayError.keychain
        }
        guard origin == currentOrigin else { return }
        hasSavedToken = false
        enabled = false
        defaults.set(false, forKey: Self.enabledKey)
        generation &+= 1
    }
}

@MainActor
@Observable
final class CRMGatewaySettingsModel {
    let settings: CRMGatewaySettings
    var enabled: Bool
    var origin: String
    var allowTailscaleHTTP: Bool
    var newToken = ""
    private(set) var isSaving = false
    private(set) var saved = false
    private(set) var error: CRMGatewayError?
    private var pendingTokenReuse: TokenReuse?
    private(set) var isCheckingGateway = false
    private(set) var gatewayRuntime: CRMGatewayRuntime?
    private(set) var gatewayStatusError: CRMGatewayError?
    private(set) var gatewayCheckedAt: Date?
    private(set) var gatewayCheckedGeneration: Int?
    @ObservationIgnored private let statusProvider: any CRMGatewayStatusProvider

    private struct TokenReuse {
        let source: String
        let destination: String
        let inputOrigin: String
        let settingsGeneration: Int
        let enabled: Bool
        let allowTailscaleHTTP: Bool
    }

    init(settings: CRMGatewaySettings = CRMGatewaySettings(), statusProvider: any CRMGatewayStatusProvider = CRMGatewayClient()) {
        self.statusProvider = statusProvider
        self.settings = settings
        enabled = settings.enabled
        origin = settings.origin
        allowTailscaleHTTP = settings.allowTailscaleHTTP
    }

    var canCheckConnection: Bool {
        !hasChanges && settings.enabled && !isSaving && !isCheckingGateway
    }

    var hasCurrentGatewayStatus: Bool {
        !hasChanges && gatewayCheckedGeneration == settings.generation
    }

    func checkConnection() async {
        guard canCheckConnection else { return }
        let generation = settings.generation
        isCheckingGateway = true
        gatewayRuntime = nil
        gatewayStatusError = nil
        gatewayCheckedAt = nil
        gatewayCheckedGeneration = nil
        defer { isCheckingGateway = false }
        do {
            let configuration = try await settings.configuration()
            let runtime = try await statusProvider.runtime(configuration: configuration)
            try Task.checkCancellation()
            guard settings.generation == generation, !hasChanges else { return }
            gatewayRuntime = runtime
        } catch is CancellationError { return }
        catch {
            guard settings.generation == generation, !hasChanges else { return }
            gatewayStatusError = (error as? CRMGatewayError) ?? .unavailable
        }
        gatewayCheckedAt = Date()
        gatewayCheckedGeneration = generation
    }

    var hasChanges: Bool {
        enabled != settings.enabled || origin != settings.origin
            || allowTailscaleHTTP != settings.allowTailscaleHTTP || !newToken.isEmpty
    }

    var savedTokenOrigin: String? {
        settings.hasSavedToken ? settings.origin : nil
    }

    var canReuseSavedToken: Bool {
        guard !isSaving, newToken.isEmpty, let source = savedTokenOrigin,
              let destination = try? CRMGatewayConfiguration.canonicalOrigin(
                origin, allowTailscaleHTTP: allowTailscaleHTTP
              ).absoluteString else { return false }
        return destination != source
    }

    var tokenReuseSource: String { pendingTokenReuse?.source ?? "" }
    var tokenReuseDestination: String { pendingTokenReuse?.destination ?? "" }

    @discardableResult
    func prepareTokenReuse() -> Bool {
        guard canReuseSavedToken,
              let destination = try? CRMGatewayConfiguration.canonicalOrigin(
                origin, allowTailscaleHTTP: allowTailscaleHTTP
              ).absoluteString else { return false }
        pendingTokenReuse = TokenReuse(
            source: settings.origin, destination: destination, inputOrigin: origin,
            settingsGeneration: settings.generation, enabled: enabled,
            allowTailscaleHTTP: allowTailscaleHTTP
        )
        return true
    }

    func cancelTokenReuse() { pendingTokenReuse = nil }

    func reuseSavedToken() async {
        guard !isSaving, let request = pendingTokenReuse else { return }
        pendingTokenReuse = nil
        guard matches(request) else { return }
        isSaving = true
        error = nil
        saved = false
        defer { isSaving = false }
        do {
            let token = try await settings.tokenForConfirmedReuse(
                from: request.source, generation: request.settingsGeneration
            )
            guard matches(request) else { return }
            try await settings.save(
                enabled: request.enabled, origin: request.destination, newToken: token,
                allowTailscaleHTTP: request.allowTailscaleHTTP
            )
            newToken = ""
            enabled = settings.enabled
            origin = settings.origin
            allowTailscaleHTTP = settings.allowTailscaleHTTP
            saved = true
        } catch let failure as CRMGatewayError {
            error = failure
        } catch {
            self.error = .keychain
        }
    }

    private func matches(_ request: TokenReuse) -> Bool {
        settings.generation == request.settingsGeneration && settings.origin == request.source
            && origin == request.inputOrigin && enabled == request.enabled
            && allowTailscaleHTTP == request.allowTailscaleHTTP && newToken.isEmpty
    }

    func save() async {
        guard !isSaving else { return }
        pendingTokenReuse = nil
        isSaving = true
        error = nil
        saved = false
        defer { isSaving = false }
        do {
            try await settings.save(
                enabled: enabled, origin: origin, newToken: newToken,
                allowTailscaleHTTP: allowTailscaleHTTP
            )
            newToken = ""
            enabled = settings.enabled
            origin = settings.origin
            allowTailscaleHTTP = settings.allowTailscaleHTTP
            saved = true
        } catch let failure as CRMGatewayError {
            error = failure
        } catch {
            self.error = .keychain
        }
    }

    func removeToken() async {
        guard !isSaving else { return }
        pendingTokenReuse = nil
        isSaving = true
        error = nil
        saved = false
        defer { isSaving = false }
        do {
            try await settings.removeToken()
            enabled = settings.enabled
            newToken = ""
        } catch {
            self.error = .keychain
        }
    }

    func discard() {
        pendingTokenReuse = nil
        enabled = settings.enabled
        origin = settings.origin
        allowTailscaleHTTP = settings.allowTailscaleHTTP
        newToken = ""
        saved = false
        error = nil
    }
}
