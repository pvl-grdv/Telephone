import Foundation
import Testing

struct CRMEmailLookupTests {
    @Test func acceptsOneCanonicalASCIIEmailAndRejectsPatternsListsAndControls() {
        #expect(CRMEmailAddress.normalize(" Person.Tag+crm@EXAMPLE.test ") == "person.tag+crm@example.test")
        for value in ["a@example", ".a@example.test", "a..b@example.test", "a@example..test",
                      "a@-example.test", "a@example-.test", "a@@example.test", "a b@example.test",
                      "a%25@example.test", "a*@example.test", "a?@example.test", "a@example.test,b@example.test",
                      "a@example.test;b@example.test", "a@example.test\n", "\ta@example.test", "ä@example.test",
                      "Name <a@example.test>", "\"a\"@example.test"] {
            #expect(CRMEmailAddress.normalize(value) == nil)
        }
    }

    @Test func sendsOnlyTypedEmailLookupAndPreservesAllInventory() async throws {
        let transport = GatewayTransportFake(data: try EmailGatewayFixture.oneMatch())
        let client = CRMGatewayClient(transport: transport)
        let response = try await client.customer(forEmail: " Person@Example.test ", companyID: nil, configuration: configuration())
        #expect(response.data?.sourceKeyId == nil)
        #expect(response.data?.company.emails == ["person@example.test"])
        #expect(response.data?.keys[0].programs.map(\.release) == ["0006", "0010"])
        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.absoluteString == "https://gateway.example/v1/customer-by-email/filter")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-email-token")
        let body = try #require(request.httpBody)
        #expect(try JSONSerialization.jsonObject(with: body) as? [String: String] == ["email": "person@example.test"])
    }

    @Test func invalidEmailNeverStartsNetworkAndMissingDiffersFromAuthorizationFailure() async throws {
        let transport = GatewayTransportFake(data: try EmailGatewayFixture.oneMatch())
        let client = CRMGatewayClient(transport: transport)
        await expectError(.invalidEmail) { try await client.customer(forEmail: "%@example.test", companyID: nil, configuration: configuration()) }
        #expect(await transport.requests.isEmpty)
        let missing = CRMGatewayClient(transport: GatewayTransportFake(data: EmailGatewayFixture.notFound))
        #expect(try await missing.customer(forEmail: "person@example.test", companyID: nil, configuration: configuration()).data == nil)
        let rejected = CRMGatewayClient(transport: GatewayTransportFake(status: 401, data: Data()))
        await expectError(.unauthorized) { try await rejected.customer(forEmail: "person@example.test", companyID: nil, configuration: configuration()) }
    }

    @Test func emailInventoryRequiresCanonicalMatchingEmailsAndExplicitValidSelection() async throws {
        let fixtures: [[String]?] = [nil, [], ["different@example.test"], ["Person@example.test"], ["person@example.test", "person@example.test"]]
        for emails in fixtures {
            let client = CRMGatewayClient(transport: GatewayTransportFake(data: try EmailGatewayFixture.oneMatch(emails: emails)))
            await expectError(.invalidResponse) { try await client.customer(forEmail: "person@example.test", companyID: nil, configuration: configuration()) }
        }
        let ambiguous = CRMGatewayClient(transport: GatewayTransportFake(data: try EmailGatewayFixture.ambiguous(includeInventory: true)))
        await expectError(.invalidResponse) { try await ambiguous.customer(forEmail: "person@example.test", companyID: nil, configuration: configuration()) }
        let transport = GatewayTransportFake(data: try EmailGatewayFixture.ambiguous(includeInventory: true))
        let selected = CRMGatewayClient(transport: transport)
        #expect(try await selected.customer(forEmail: "person@example.test", companyID: 1200456, configuration: configuration()).data?.company.id == 1200456)
        let body = try #require(await transport.requests.first?.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["email"] as? String == "person@example.test")
        #expect(json["companyId"] as? Int == 1200456)
        #expect(Set(json.keys) == ["email", "companyId"])
    }

    private func configuration() throws -> CRMGatewayConfiguration {
        try CRMGatewayConfiguration(origin: "https://gateway.example", token: "fictional-email-token")
    }

    private func expectError(_ expected: CRMGatewayError, operation: () async throws -> CRMPhoneLookupResponse) async {
        do { _ = try await operation(); Issue.record("Expected typed email lookup failure") }
        catch let error as CRMGatewayError { #expect(error == expected) }
        catch { Issue.record("Unexpected email lookup error type") }
    }
}

@MainActor
struct CRMEmailLookupModelTests {
    @Test func ambiguousEmailSelectionUsesEmailAgainAndNeverOffersPhoneAppend() async throws {
        let fixture = try await makeFixture()
        fixture.model.setCallerPhone("70005550101", isActive: true)
        await waitUntilFinished(fixture.model)
        fixture.model.email = " Person@Example.test "
        fixture.model.searchEmail()
        await waitUntilFinished(fixture.model)
        guard case .choosing(let matches) = fixture.model.state else { Issue.record("Expected email choices"); return }
        fixture.model.chooseCompany(matches[0])
        await waitUntilFinished(fixture.model)
        #expect(await fixture.provider.emailCalls.map(\.email) == ["person@example.test", "person@example.test"])
        #expect(await fixture.provider.emailCalls.map(\.companyID) == [nil, 1200456])
        #expect(await fixture.provider.phoneCalls == 1)
        #expect(await fixture.provider.appendCalls == 0)
        #expect(!fixture.model.canLinkPhone)
        #expect(!fixture.model.isCallerAlreadyLinked)
        fixture.model.preparePhoneLink()
        #expect(fixture.model.pendingPhoneLink == nil)
    }

    @Test func editingEmailOrCancellingRejectsLateEmailResponses() async throws {
        for edit in [true, false] {
            let fixture = try await makeFixture(hold: true)
            fixture.model.email = "person@example.test"
            fixture.model.searchEmail()
            await fixture.provider.waitForRequest()
            if edit { fixture.model.email = "other@example.test" } else { fixture.model.cancel() }
            await fixture.provider.finishPending()
            for _ in 0..<30 { await Task.yield() }
            #expect(fixture.model.state == .idle)
            #expect(await fixture.provider.appendCalls == 0)
        }
    }

    private func makeFixture(hold: Bool = false) async throws -> EmailModelFixture {
        let defaults = UserDefaults(suiteName: "EmailLookupTests.\(UUID().uuidString)")!
        let settings = CRMGatewaySettings(defaults: defaults, tokenStore: EmailTokenFake())
        try await settings.save(enabled: true, origin: "https://gateway.example", newToken: "fictional-email-token")
        let provider = EmailModelProviderFake(hold: hold)
        return EmailModelFixture(model: CRMKeyLookupModel(settings: settings, provider: provider), provider: provider)
    }

    private func waitUntilFinished(_ model: CRMKeyLookupModel) async {
        for _ in 0..<100 where model.state == .loading { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(model.state != .loading)
    }
}

enum EmailGatewayFixture {
    static let notFound = Data(#"{"data":null,"matches":[],"meta":{"requestId":"fictional-email-none","fetchedAt":"2026-01-01T12:00:00Z","complete":true,"fromCache":false}}"#.utf8)

    static func oneMatch(emails: [String]? = ["person@example.test"]) throws -> Data {
        try addingEmails(to: PhoneGatewayFixture.oneMatch(), emails: emails)
    }

    static func ambiguous(includeInventory: Bool = false) throws -> Data {
        try addingEmails(to: PhoneGatewayFixture.ambiguous(includeInventory: includeInventory), emails: ["person@example.test"])
    }

    private static func addingEmails(to data: Data, emails: [String]?) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        if var customer = object["data"] as? [String: Any], var company = customer["company"] as? [String: Any] {
            company["emails"] = emails
            company["phone"] = nil
            company["phones"] = [String]()
            customer["company"] = company
            object["data"] = customer
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}

@MainActor
private struct EmailModelFixture { let model: CRMKeyLookupModel; let provider: EmailModelProviderFake }

private actor EmailTokenFake: CRMGatewayTokenStoring {
    var values: [String: String] = [:]
    func token(for origin: String) -> String { values[origin] ?? "" }
    func save(_ token: String, for origin: String) -> Bool { values[origin] = token; return true }
    func remove(for origin: String) -> Bool { values.removeValue(forKey: origin); return true }
}

private actor EmailModelProviderFake: CRMKeyLookupProvider {
    struct Call: Sendable { let email: String; let companyID: Int? }
    let hold: Bool
    private var pending: CheckedContinuation<Void, Never>?
    private var ready: CheckedContinuation<Void, Never>?
    private(set) var emailCalls: [Call] = []
    private(set) var phoneCalls = 0
    private(set) var appendCalls = 0
    init(hold: Bool) { self.hold = hold }
    func customer(forKeyNumber keyNumber: Int, configuration: CRMGatewayConfiguration) throws -> CRMKeyLookupResponse { throw CRMGatewayError.invalidResponse }
    func customer(forPhoneNumber phoneNumber: String, companyID: Int?, configuration: CRMGatewayConfiguration) throws -> CRMPhoneLookupResponse { phoneCalls += 1; throw CRMGatewayError.invalidResponse }
    func customer(forEmail email: String, companyID: Int?, configuration: CRMGatewayConfiguration) async throws -> CRMPhoneLookupResponse {
        emailCalls.append(Call(email: email, companyID: companyID))
        if hold { await withCheckedContinuation { pending = $0; ready?.resume(); ready = nil } }
        return try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: EmailGatewayFixture.ambiguous(includeInventory: companyID != nil))
    }
    func appendPhone(_ phoneNumber: String, companyID: Int, sourceKeyID: Int, expectedPhone: String, configuration: CRMGatewayConfiguration) throws -> CRMPhoneAppendResponse { appendCalls += 1; throw CRMGatewayError.forbidden }
    func waitForRequest() async { if pending != nil { return }; await withCheckedContinuation { ready = $0 } }
    func finishPending() { pending?.resume(); pending = nil }
}
