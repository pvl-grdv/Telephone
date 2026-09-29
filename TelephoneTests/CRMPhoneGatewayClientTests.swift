import Foundation
import Testing

struct CRMPhoneGatewayClientTests {
    @Test func callerLookupUsesItsOwnRouteAndNormalizedPhoneOnly() async throws {
        let transport = GatewayTransportFake(data: try PhoneGatewayFixture.oneMatch())
        let client = CRMGatewayClient(transport: transport)
        let result = try await client.customer(
            forPhoneNumber: "8 (000) 555-01-01", companyID: nil, configuration: configuration()
        )
        #expect(result.matches.count == 1)
        #expect(result.data?.sourceKeyId == nil)
        #expect(result.data?.company.phone == "+70005550101")
        #expect(result.data?.company.phones == ["+70005550101"])
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/v1/customer-by-phone/filter")
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(json.keys) == ["phoneNumber"])
        #expect(json["phoneNumber"] as? String == "+70005550101")
    }

    @Test func ambiguityNeverSelectsAnOwnerAutomatically() async throws {
        let client = CRMGatewayClient(transport: GatewayTransportFake(data: try PhoneGatewayFixture.ambiguous()))
        let result = try await client.customer(
            forPhoneNumber: "+70005550101", companyID: nil, configuration: configuration()
        )
        #expect(result.data == nil)
        #expect(result.matches.count == 2)
        let invalid = CRMGatewayClient(transport: GatewayTransportFake(data: try PhoneGatewayFixture.ambiguous(includeInventory: true)))
        await expectError(.invalidResponse) {
            _ = try await invalid.customer(forPhoneNumber: "+70005550101", companyID: nil, configuration: configuration())
        }
    }

    @Test func explicitChoiceIsRecheckedByGatewayAndResponseMustMatch() async throws {
        let transport = GatewayTransportFake(data: try PhoneGatewayFixture.ambiguous(includeInventory: true))
        let client = CRMGatewayClient(transport: transport)
        let result = try await client.customer(
            forPhoneNumber: "+70005550101", companyID: 1200456, configuration: configuration()
        )
        #expect(result.data?.company.id == 1200456)
        let request = try #require(await transport.requests.first)
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(json.keys) == ["phoneNumber", "companyId"])
        #expect(json["companyId"] as? Int == 1200456)
        await expectError(.invalidResponse) {
            _ = try await client.customer(forPhoneNumber: "+70005550101", companyID: 2200456, configuration: configuration())
        }
    }

    @Test func appendSendsOnlyOneNarrowOperationAndExactPhoneSnapshot() async throws {
        let transport = GatewayTransportFake(data: try PhoneGatewayFixture.appended())
        let client = CRMGatewayClient(transport: transport)
        let original = "+12025550100, legacy text"
        let result = try await client.appendPhone(
            "70005550101", companyID: 1200456, sourceKeyID: 76543,
            expectedPhone: original, configuration: configuration()
        )
        #expect(result.data.added)
        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.path == "/v1/customer-phone/append")
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(json.keys) == ["companyId", "sourceKeyId", "phoneNumber", "expectedPhone"])
        #expect(json["phoneNumber"] as? String == "+70005550101")
        #expect(json["expectedPhone"] as? String == original)
    }

    @Test(arguments: [403, 409, 503])
    func appendPermissionConflictAndUnavailableAreDistinct(_ status: Int) async throws {
        let transport = GatewayTransportFake(status: status, data: Data())
        let client = CRMGatewayClient(transport: transport)
        let expected: CRMGatewayError = status == 403 ? .forbidden : status == 409 ? .conflict : .unavailable
        await expectError(expected) {
            _ = try await client.appendPhone(
                "+70005550101", companyID: 1200456, sourceKeyID: 76543,
                expectedPhone: "", configuration: configuration()
            )
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func invalidCallerPhoneNeverStartsNetworking() async throws {
        let transport = GatewayTransportFake(data: try PhoneGatewayFixture.oneMatch())
        let client = CRMGatewayClient(transport: transport)
        await expectError(.invalidPhoneNumber) {
            _ = try await client.customer(forPhoneNumber: "alice123", companyID: nil, configuration: configuration())
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func unconfirmedServerWriteAndTransportFailureRequireRefresh() async throws {
        let body = Data(#"{"error":{"code":"PHONE_WRITE_UNCONFIRMED"}}"#.utf8)
        let clients = [
            CRMGatewayClient(transport: GatewayTransportFake(status: 503, data: body)),
            CRMGatewayClient(transport: PhoneTransportFailureFake()),
        ]
        for client in clients {
            await expectError(.phoneWriteUnconfirmed) {
                _ = try await client.appendPhone(
                    "+70005550101", companyID: 1200456, sourceKeyID: 76543,
                    expectedPhone: "", configuration: configuration()
                )
            }
        }
    }

    @Test func canonicalCRMPhoneArraysAreValidatedAndUsedBeforeRawLocalPhones() async throws {
        var root = try JSONSerialization.jsonObject(with: PhoneGatewayFixture.oneMatch()) as! [String: Any]
        var customer = root["data"] as! [String: Any]
        var company = customer["company"] as! [String: Any]
        company["phone"] = "555-01-01"
        customer["company"] = company
        root["data"] = customer
        let valid = CRMGatewayClient(transport: GatewayTransportFake(data: try JSONSerialization.data(withJSONObject: root)))
        let response = try await valid.customer(forPhoneNumber: "+70005550101", companyID: nil, configuration: configuration())
        #expect(response.data?.company.containsPhone("8 (000) 555-01-01") == true)
        for phones in [["70005550101"], ["+70005550101", "+70005550101"], ["+70005550102"]] {
            company["phones"] = phones
            customer["company"] = company
            root["data"] = customer
            let invalid = CRMGatewayClient(transport: GatewayTransportFake(data: try JSONSerialization.data(withJSONObject: root)))
            await expectError(.invalidResponse) {
                _ = try await invalid.customer(forPhoneNumber: "+70005550101", companyID: nil, configuration: configuration())
            }
        }
    }

    private func configuration() throws -> CRMGatewayConfiguration {
        try CRMGatewayConfiguration(origin: "https://gateway.example", token: "fictional-test-token")
    }

    private func expectError(_ expected: CRMGatewayError, operation: () async throws -> Void) async {
        do {
            try await operation()
            Issue.record("Expected a gateway error")
        } catch let error as CRMGatewayError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error type")
        }
    }
}

private struct PhoneTransportFailureFake: CRMGatewayHTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.timedOut)
    }
}

enum PhoneGatewayFixture {
    static func keyCustomer() throws -> Data {
        var root = try rootObject()
        var customer = root["data"] as! [String: Any]
        var company = customer["company"] as! [String: Any]
        company["phone"] = "+12025550100, legacy text"
        company["phones"] = ["+12025550100"]
        customer["company"] = company
        root["data"] = customer
        return try JSONSerialization.data(withJSONObject: root)
    }

    static func oneMatch() throws -> Data {
        var root = try rootObject()
        var customer = root["data"] as! [String: Any]
        customer["sourceKeyId"] = NSNull()
        var company = customer["company"] as! [String: Any]
        company["phone"] = "+70005550101"
        company["phones"] = ["+70005550101"]
        customer["company"] = company
        root["data"] = customer
        root["matches"] = [match(1200456, name: "Example Company")]
        return try JSONSerialization.data(withJSONObject: root)
    }

    static func ambiguous(includeInventory: Bool = false) throws -> Data {
        var root = try JSONSerialization.jsonObject(with: oneMatch()) as! [String: Any]
        if !includeInventory { root["data"] = NSNull() }
        root["matches"] = [match(1200456, name: "Example Company"), match(2200456, name: "Other Example Company")]
        return try JSONSerialization.data(withJSONObject: root)
    }

    static func appended(added: Bool = true) throws -> Data {
        let root = try rootObject()
        return try JSONSerialization.data(withJSONObject: [
            "data": ["companyId": 1200456, "phone": "+12025550100, legacy text, +70005550101", "phones": ["+12025550100", "+70005550101"], "added": added],
            "meta": root["meta"]!,
        ])
    }

    private static func rootObject() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: GatewayFixture.customer) as! [String: Any]
    }

    private static func match(_ id: Int, name: String) -> [String: Any] {
        ["id": id, "name": name, "formattedCode": "98-76-5432"]
    }
}
