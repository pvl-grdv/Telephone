//
//  CRMKeyLookupModelTests.swift
//  TelephoneTests
//

import Foundation
import Testing

@MainActor
struct CRMKeyLookupModelTests {
    @Test func disabledByDefaultAndTokenIsScopedToCanonicalOrigin() async throws {
        let defaults = freshDefaults()
        let tokens = GatewayTokenStoreFake()
        let settings = CRMGatewaySettings(defaults: defaults, tokenStore: tokens)
        #expect(!settings.enabled)
        #expect(settings.origin.isEmpty)
        try await settings.save(enabled: true, origin: "https://GATEWAY.example:443/", newToken: "fictional-one")
        #expect(settings.origin == "https://gateway.example")
        #expect(try await settings.configuration().token == "fictional-one")
        #expect(await tokens.token(for: "https://different.example").isEmpty)

        do {
            try await settings.save(enabled: true, origin: "https://different.example", newToken: "")
            Issue.record("A different origin must require its own token")
        } catch let error as CRMGatewayError {
            #expect(error == .missingToken)
        }
        #expect(settings.origin == "https://gateway.example")
        #expect(defaults.dictionaryRepresentation().values.contains { ($0 as? String) == "fictional-one" } == false)
        try await settings.removeToken()
        #expect(!settings.enabled)
        #expect(await tokens.token(for: "https://gateway.example").isEmpty)
    }

    @Test func tailscaleHTTPOptInPersistsAndRequiresItsOwnToken() async throws {
        let defaults = freshDefaults()
        let tokens = GatewayTokenStoreFake()
        let settings = CRMGatewaySettings(defaults: defaults, tokenStore: tokens)
        #expect(!settings.allowTailscaleHTTP)
        try await settings.save(
            enabled: true, origin: "https://gateway.example", newToken: "fictional-https-token"
        )

        do {
            try await settings.save(
                enabled: true, origin: "http://100.64.1.2:8787", newToken: "",
                allowTailscaleHTTP: true
            )
            Issue.record("An IP origin must not inherit the HTTPS token")
        } catch let error as CRMGatewayError {
            #expect(error == .missingToken)
        }
        #expect(settings.origin == "https://gateway.example")

        try await settings.save(
            enabled: true, origin: "http://100.64.1.2:8787", newToken: "fictional-ip-token",
            allowTailscaleHTTP: true
        )
        #expect(settings.allowTailscaleHTTP)
        #expect(settings.origin == "http://100.64.1.2:8787")
        #expect(try await settings.configuration().token == "fictional-ip-token")
        #expect(await tokens.token(for: "https://gateway.example") == "fictional-https-token")
        #expect(await tokens.token(for: "http://100.64.1.2:8787") == "fictional-ip-token")

        let reloaded = CRMGatewaySettings(defaults: defaults, tokenStore: tokens)
        #expect(reloaded.allowTailscaleHTTP)
        #expect(try await reloaded.configuration().origin.absoluteString == "http://100.64.1.2:8787")
        do {
            try await reloaded.save(
                enabled: true, origin: "http://100.64.1.2:8787", newToken: "",
                allowTailscaleHTTP: false
            )
            Issue.record("Turning off the opt-in must reject an HTTP origin")
        } catch let error as CRMGatewayError {
            #expect(error == .invalidOrigin)
        }
        #expect(reloaded.allowTailscaleHTTP)
        try await reloaded.save(
            enabled: true, origin: "https://gateway.example", newToken: "",
            allowTailscaleHTTP: false
        )
        #expect(!reloaded.allowTailscaleHTTP)
        #expect(try await reloaded.configuration().token == "fictional-https-token")
    }

    @Test func lateResponseFromPreviousCallCannotPopulateTheNextCall() async throws {
        let fixture = try await makeFixture()
        let model = fixture.model
        model.keyNumber = "76543"
        model.search()
        await fixture.provider.waitForRequest(76543)
        #expect(model.state == .loading)
        model.resetContext()
        try await fixture.provider.finish(76543, with: response())
        await allowTaskToFinish()
        #expect(model.keyNumber.isEmpty)
        #expect(model.state == .idle)
    }

    @Test func changedSettingsRejectAlreadyPendingResultsEvenBeforeViewUpdates() async throws {
        let fixture = try await makeFixture()
        fixture.model.keyNumber = "76543"
        fixture.model.search()
        await fixture.provider.waitForRequest(76543)
        try await fixture.settings.save(enabled: false, origin: "https://gateway.example", newToken: "")
        try await fixture.provider.finish(76543, with: response())
        await allowTaskToFinish()
        fixture.model.settingsDidChange()
        #expect(fixture.model.state == .idle)
        #expect(!fixture.model.canSearch)
    }

    @Test func changedQueryAndExplicitCancelIgnoreUncooperativeProviders() async throws {
        let fixture = try await makeFixture()
        fixture.model.keyNumber = "76543"
        fixture.model.search()
        await fixture.provider.waitForRequest(76543)
        fixture.model.keyNumber = "76544"
        #expect(fixture.model.state == .idle)
        try await fixture.provider.finish(76543, with: response())
        await allowTaskToFinish()
        #expect(fixture.model.state == .idle)

        fixture.model.search()
        await fixture.provider.waitForRequest(76544)
        fixture.model.cancel()
        try await fixture.provider.finish(76544, with: response())
        await allowTaskToFinish()
        #expect(fixture.model.state == .idle)
    }

    @Test func displaysNotFoundSeparatelyFromUnavailable() async throws {
        let fixture = try await makeFixture()
        fixture.model.keyNumber = "76543"
        fixture.model.search()
        await fixture.provider.waitForRequest(76543)
        let missing = try JSONDecoder().decode(CRMKeyLookupResponse.self, from: GatewayFixture.notFound)
        await fixture.provider.finish(76543, with: missing)
        await waitUntilFinished(fixture.model)
        #expect(fixture.model.state == .notFound)

        fixture.model.search()
        await fixture.provider.waitForRequest(76543)
        await fixture.provider.fail(76543, with: .unavailable)
        await waitUntilFinished(fixture.model)
        #expect(fixture.model.state == .failed(.unavailable))
    }

    private func makeFixture() async throws -> LookupFixture {
        let settings = CRMGatewaySettings(defaults: freshDefaults(), tokenStore: GatewayTokenStoreFake())
        try await settings.save(enabled: true, origin: "https://gateway.example", newToken: "fictional-test-token")
        let provider = DelayedGatewayProvider()
        return LookupFixture(
            settings: settings,
            provider: provider,
            model: CRMKeyLookupModel(settings: settings, provider: provider)
        )
    }

    private func response() throws -> CRMKeyLookupResponse {
        try JSONDecoder().decode(CRMKeyLookupResponse.self, from: GatewayFixture.customer)
    }

    private func allowTaskToFinish() async {
        for _ in 0..<30 { await Task.yield() }
    }

    private func waitUntilFinished(_ model: CRMKeyLookupModel) async {
        for _ in 0..<100 where model.state == .loading {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.state != .loading)
    }

    private func freshDefaults() -> UserDefaults {
        let name = "CRMGatewayTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

@MainActor
private struct LookupFixture {
    let settings: CRMGatewaySettings
    let provider: DelayedGatewayProvider
    let model: CRMKeyLookupModel
}

private actor GatewayTokenStoreFake: CRMGatewayTokenStoring {
    private var tokens: [String: String] = [:]

    func token(for origin: String) -> String { tokens[origin] ?? "" }
    func save(_ token: String, for origin: String) -> Bool {
        tokens[origin] = token
        return true
    }
    func remove(for origin: String) -> Bool {
        tokens.removeValue(forKey: origin)
        return true
    }
}

private actor DelayedGatewayProvider: CRMKeyLookupProvider {
    private var requests: [Int: CheckedContinuation<CRMKeyLookupResponse, any Error>] = [:]
    private var ready: [Int: CheckedContinuation<Void, Never>] = [:]

    func customer(
        forKeyNumber keyNumber: Int,
        configuration: CRMGatewayConfiguration
    ) async throws -> CRMKeyLookupResponse {
        // Intentionally ignores cancellation, so the model must reject stale results.
        try await withCheckedThrowingContinuation { continuation in
            requests[keyNumber] = continuation
            ready.removeValue(forKey: keyNumber)?.resume()
        }
    }

    func waitForRequest(_ key: Int) async {
        guard requests[key] == nil else { return }
        await withCheckedContinuation { ready[key] = $0 }
    }

    func finish(_ key: Int, with response: CRMKeyLookupResponse) {
        requests.removeValue(forKey: key)?.resume(returning: response)
    }

    func fail(_ key: Int, with error: CRMGatewayError) {
        requests.removeValue(forKey: key)?.resume(throwing: error)
    }
}
