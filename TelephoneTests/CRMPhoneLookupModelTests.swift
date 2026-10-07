import Foundation
import Testing

@MainActor
struct CRMPhoneLookupModelTests {
    @Test func automaticallyLooksUpOnlyEligibleActualCallerPhones() async throws {
        let fixture = try await makeFixture(phoneData: PhoneGatewayFixture.oneMatch())
        fixture.model.setCallerPhone("alice123", isActive: true)
        #expect(await fixture.provider.phoneCalls.isEmpty)
        fixture.model.setCallerPhone("8 (000) 555-01-01", isActive: true)
        await waitUntilFinished(fixture.model)
        #expect(await fixture.provider.phoneCalls == ["+70005550101"])
        #expect(fixture.model.isCallerAlreadyLinked)
        #expect(!fixture.model.canLinkPhone)
        #expect(await fixture.provider.appendCalls.isEmpty)
        fixture.model.activateContext()
        #expect(await fixture.provider.phoneCalls.count == 1)
    }

    @Test func ambiguousPhoneRequiresAChoiceAndNeverWritesAutomatically() async throws {
        let fixture = try await makeFixture(phoneData: PhoneGatewayFixture.ambiguous())
        fixture.model.setCallerPhone("70005550101", isActive: true)
        await waitUntilFinished(fixture.model)
        guard case .choosing(let matches) = fixture.model.state else {
            Issue.record("Expected explicit organization choices")
            return
        }
        #expect(matches.count == 2)
        #expect(await fixture.provider.appendCalls.isEmpty)
        fixture.model.chooseCompany(matches[0])
        await waitUntilFinished(fixture.model)
        #expect(await fixture.provider.companyChoices == [nil, 1200456])
        #expect(fixture.model.isCallerAlreadyLinked)
        #expect(!fixture.model.canLinkPhone)
    }

    @Test func manualKeyLookupOnlyAppendsAfterExplicitMatchingConfirmation() async throws {
        let fixture = try await manualKeyFixture()
        #expect(fixture.model.canLinkPhone)
        #expect(await fixture.provider.appendCalls.isEmpty)
        fixture.model.preparePhoneLink()
        let confirmation = try #require(fixture.model.pendingPhoneLink)
        #expect(confirmation.phone == "+70005550101")
        #expect(confirmation.companyName == "Example Company")
        #expect(confirmation.expectedPhone == "+12025550100, legacy text")
        #expect(await fixture.provider.appendCalls.isEmpty)
        fixture.model.confirmPhoneLink(confirmation)
        await waitForWrite(fixture.model)
        let calls = await fixture.provider.appendCalls
        #expect(calls.count == 1)
        #expect(calls.first?.companyID == 1200456)
        #expect(calls.first?.sourceKeyID == 76543)
        #expect(calls.first?.expectedPhone == "+12025550100, legacy text")
        #expect(fixture.model.phoneLinkState == .saved(added: true))
        #expect(!fixture.model.canLinkPhone)
        guard case .loaded(let response) = fixture.model.state else {
            Issue.record("Inventory should stay visible after linking")
            return
        }
        #expect(response.data?.company.phone == "+12025550100, legacy text, +70005550101")
    }

    @Test func aChangedCallInvalidatesAnOpenPhoneLinkConfirmation() async throws {
        let fixture = try await manualKeyFixture()
        fixture.model.preparePhoneLink()
        let oldConfirmation = try #require(fixture.model.pendingPhoneLink)
        fixture.model.resetContext()
        fixture.model.confirmPhoneLink(oldConfirmation)
        #expect(await fixture.provider.appendCalls.isEmpty)
        #expect(fixture.model.pendingPhoneLink == nil)
    }

    @Test func changedGatewaySettingsInvalidateConfirmationBeforeObservationDelivery() async throws {
        let fixture = try await manualKeyFixture()
        fixture.model.preparePhoneLink()
        let oldConfirmation = try #require(fixture.model.pendingPhoneLink)
        try await fixture.settings.save(enabled: true, origin: "https://other.example", newToken: "fictional-other-token")
        fixture.model.confirmPhoneLink(oldConfirmation)
        #expect(await fixture.provider.appendCalls.isEmpty)
    }

    @Test(arguments: [CRMGatewayError.conflict, .phoneWriteUnconfirmed, .unavailable, .forbidden])
    func failedAppendBlocksAnotherAppendUntilFreshKeyLookup(_ error: CRMGatewayError) async throws {
        let fixture = try await manualKeyFixture()
        await fixture.provider.setAppendError(error)
        fixture.model.preparePhoneLink()
        let confirmation = try #require(fixture.model.pendingPhoneLink)
        fixture.model.confirmPhoneLink(confirmation)
        await waitForWrite(fixture.model)
        let expected: CRMGatewayError = error == .unavailable ? .phoneWriteUnconfirmed : error
        #expect(fixture.model.phoneLinkState == .failed(expected))
        #expect(!fixture.model.canLinkPhone)
        fixture.model.preparePhoneLink()
        #expect(fixture.model.pendingPhoneLink == nil)
        #expect(await fixture.provider.appendCalls.count == 1)
        fixture.model.search()
        await waitUntilFinished(fixture.model)
        #expect(fixture.model.canLinkPhone)
        #expect(await fixture.provider.appendCalls.count == 1)
    }

    @Test func closingContextCancelsAndDoesNotRestartAutomaticLookup() async throws {
        let fixture = try await makeFixture(phoneData: PhoneGatewayFixture.oneMatch())
        fixture.model.setCallerPhone("70005550101", isActive: false)
        #expect(await fixture.provider.phoneCalls.isEmpty)
        fixture.model.activateContext()
        await waitUntilFinished(fixture.model)
        fixture.model.deactivateContext()
        try await fixture.settings.save(enabled: true, origin: "https://gateway.example", newToken: "fictional-updated-token")
        fixture.model.settingsDidChange()
        #expect(await fixture.provider.phoneCalls.count == 1)
        #expect(fixture.model.state == .idle)
    }

    @Test func cancelledDispatchedAppendSurvivesNewWindowAndNeedsAnotherFreshRead() async throws {
        let fixture = try await manualKeyFixture()
        await fixture.provider.holdNextAppend()
        fixture.model.preparePhoneLink()
        let confirmation = try #require(fixture.model.pendingPhoneLink)
        fixture.model.confirmPhoneLink(confirmation)
        await fixture.provider.waitForAppend()
        fixture.model.deactivateContext()
        fixture.model.cancel()
        #expect(fixture.model.phoneLinkState == .failed(.phoneWriteUnconfirmed))
        let reopened = CRMKeyLookupModel(settings: fixture.settings, provider: fixture.provider, appendRegistry: fixture.registry)
        reopened.setCallerPhone("70005550101", isActive: false)
        reopened.keyNumber = "76543"
        reopened.activateContext()
        await waitUntilFinished(reopened)
        reopened.search()
        await waitUntilFinished(reopened)
        #expect(reopened.phoneLinkState == .failed(.phoneWriteUnconfirmed))
        #expect(!reopened.canLinkPhone)
        reopened.preparePhoneLink()
        #expect(reopened.pendingPhoneLink == nil)
        #expect(await fixture.provider.appendCalls.count == 1)
        await fixture.provider.finishAppend()
        for _ in 0..<30 { await Task.yield() }
        #expect(reopened.phoneLinkState == .failed(.phoneWriteUnconfirmed))
        #expect(!reopened.canLinkPhone)
        reopened.search()
        await waitUntilFinished(reopened)
        #expect(reopened.canLinkPhone)
        #expect(await fixture.provider.appendCalls.count == 1)
    }

    private func manualKeyFixture() async throws -> PhoneModelFixture {
        let missing = Data(#"""
        {"data":null,"matches":[],"meta":{"requestId":"fictional-missing","fetchedAt":"2026-01-01T12:00:00Z","complete":true,"fromCache":false}}
        """#.utf8)
        let fixture = try await makeFixture(phoneData: missing)
        fixture.model.setCallerPhone("70005550101", isActive: true)
        await waitUntilFinished(fixture.model)
        #expect(fixture.model.state == .notFound)
        fixture.model.keyNumber = "76543"
        fixture.model.search()
        await waitUntilFinished(fixture.model)
        return fixture
    }

    private func makeFixture(phoneData: Data) async throws -> PhoneModelFixture {
        let defaults = UserDefaults(suiteName: "PhoneLookupTests.\(UUID().uuidString)")!
        let settings = CRMGatewaySettings(defaults: defaults, tokenStore: PhoneTestTokenStore())
        try await settings.save(enabled: true, origin: "https://gateway.example", newToken: "fictional-test-token")
        let provider = PhoneModelProviderFake(phoneData: phoneData)
        let registry = CRMPhoneAppendRegistry()
        return PhoneModelFixture(settings: settings, provider: provider, registry: registry, model: CRMKeyLookupModel(settings: settings, provider: provider, appendRegistry: registry))
    }

    private func waitUntilFinished(_ model: CRMKeyLookupModel) async {
        for _ in 0..<100 where model.state == .loading { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(model.state != .loading)
    }

    private func waitForWrite(_ model: CRMKeyLookupModel) async {
        for _ in 0..<100 where model.phoneLinkState == .saving { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(model.phoneLinkState != .saving)
    }
}

@MainActor
private struct PhoneModelFixture {
    let settings: CRMGatewaySettings
    let provider: PhoneModelProviderFake
    let registry: CRMPhoneAppendRegistry
    let model: CRMKeyLookupModel
}

private actor PhoneTestTokenStore: CRMGatewayTokenStoring {
    var tokens: [String: String] = [:]
    func token(for origin: String) -> String { tokens[origin] ?? "" }
    func save(_ token: String, for origin: String) -> Bool { tokens[origin] = token; return true }
    func remove(for origin: String) -> Bool { tokens.removeValue(forKey: origin); return true }
}

private actor PhoneModelProviderFake: CRMKeyLookupProvider {
    struct AppendCall: Sendable {
        let phone: String
        let companyID: Int
        let sourceKeyID: Int
        let expectedPhone: String
    }

    let phoneData: Data
    private(set) var phoneCalls: [String] = []
    private(set) var companyChoices: [Int?] = []
    private(set) var appendCalls: [AppendCall] = []
    private var appendError: CRMGatewayError?
    private var holdAppend = false
    private var pendingAppend: CheckedContinuation<Void, Never>?
    private var appendReady: CheckedContinuation<Void, Never>?

    init(phoneData: Data) { self.phoneData = phoneData }

    func customer(forKeyNumber keyNumber: Int, configuration: CRMGatewayConfiguration) throws -> CRMKeyLookupResponse {
        try JSONDecoder().decode(CRMKeyLookupResponse.self, from: PhoneGatewayFixture.keyCustomer())
    }

    func customer(forPhoneNumber phoneNumber: String, companyID: Int?, configuration: CRMGatewayConfiguration) throws -> CRMPhoneLookupResponse {
        phoneCalls.append(phoneNumber)
        companyChoices.append(companyID)
        let data = try companyID == nil ? phoneData : PhoneGatewayFixture.ambiguous(includeInventory: true)
        return try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: data)
    }

    func appendPhone(_ phoneNumber: String, companyID: Int, sourceKeyID: Int, expectedPhone: String, configuration: CRMGatewayConfiguration) async throws -> CRMPhoneAppendResponse {
        appendCalls.append(AppendCall(phone: phoneNumber, companyID: companyID, sourceKeyID: sourceKeyID, expectedPhone: expectedPhone))
        if holdAppend {
            holdAppend = false
            await withCheckedContinuation { continuation in
                pendingAppend = continuation
                appendReady?.resume()
                appendReady = nil
            }
        }
        if let appendError { throw appendError }
        return try JSONDecoder().decode(CRMPhoneAppendResponse.self, from: PhoneGatewayFixture.appended())
    }

    func setAppendError(_ error: CRMGatewayError) { appendError = error }
    func holdNextAppend() { holdAppend = true }
    func waitForAppend() async {
        if pendingAppend != nil { return }
        await withCheckedContinuation { appendReady = $0 }
    }
    func finishAppend() { pendingAppend?.resume(); pendingAppend = nil }
}
