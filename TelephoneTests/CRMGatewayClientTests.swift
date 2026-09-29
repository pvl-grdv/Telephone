//
//  CRMGatewayClientTests.swift
//  TelephoneTests
//

import Foundation
import Synchronization
import Testing

struct CRMGatewayClientTests {
    @Test func originRequiresHTTPSAndRejectsPathsAndCredentials() throws {
        for origin in [
            "http://gateway.example", "https://gateway.example/api",
            "https://user:password@gateway.example", "https://gateway.example?key=1",
            "https://gateway.example/#fragment", "https://gateway.example:0",
        ] {
            #expect(throws: CRMGatewayError.invalidOrigin) {
                try CRMGatewayConfiguration.canonicalOrigin(origin)
            }
        }
        #expect(
            try CRMGatewayConfiguration.canonicalOrigin(" https://GATEWAY.example:443/ ").absoluteString
                == "https://gateway.example"
        )
        #expect(throws: CRMGatewayError.missingToken) {
            try CRMGatewayConfiguration(origin: "https://gateway.example", token: "token\r\nInjected: yes")
        }
    }

    @Test func sendsOnlyTheGatewayLookupAndPreservesAllProgramRecords() async throws {
        let transport = GatewayTransportFake(data: GatewayFixture.customer)
        let sut = CRMGatewayClient(transport: transport)
        let response = try await sut.customer(forKeyNumber: 76543, configuration: configuration())
        let customer = try #require(response.data)
        #expect(customer.company.id == 1200456)
        #expect(customer.company.formattedCode == "98-76-5432")
        #expect(customer.keys.count == 2)
        #expect(customer.keys[0].programs.count == 2)
        #expect(customer.keys[0].programs.map(\.release) == ["0006", "0010"])
        #expect(customer.keys[0].programs.map(\.programId) == [1000, 1000])
        #expect(customer.keys[1].programs.isEmpty)
        #expect(customer.keys[0].url.absoluteString == "https://integral.ru/personal/keys/01-20-0456/76543/")
        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.absoluteString == "https://gateway.example/v1/customer-by-key/filter")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-test-token")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Int])
        #expect(json == ["keyNumber": 76543])
    }

    @Test func notFoundIsSuccessfulAndDifferentFromAuthorizationFailure() async throws {
        let missing = CRMGatewayClient(transport: GatewayTransportFake(data: GatewayFixture.notFound))
        #expect(try await missing.customer(forKeyNumber: 76543, configuration: configuration()).data == nil)
        let unauthorized = CRMGatewayClient(transport: GatewayTransportFake(status: 401, data: Data()))
        await expectError(.unauthorized) {
            try await unauthorized.customer(forKeyNumber: 76543, configuration: configuration())
        }
    }

    @Test(arguments: [403, 429, 302, 503, 504, 404])
    func classifiesHTTPFailuresWithoutDecodingTheirBodies(_ status: Int) async throws {
        let expected: CRMGatewayError
        switch status {
        case 403: expected = .unauthorized
        case 429: expected = .rateLimited
        case 302: expected = .redirectDenied
        case 503, 504: expected = .unavailable
        default: expected = .invalidResponse
        }
        let client = CRMGatewayClient(transport: GatewayTransportFake(status: status, data: Data()))
        await expectError(expected) {
            try await client.customer(forKeyNumber: 76543, configuration: configuration())
        }
    }

    @Test func rejectsIncompleteForeignOrUnsafeResponses() async throws {
        let sample = String(decoding: GatewayFixture.customer, as: UTF8.self)
        let fixtures = [
            sample.replacingOccurrences(of: "\"complete\":true", with: "\"complete\":false"),
            sample.replacingOccurrences(of: "\"sourceKeyId\":76543", with: "\"sourceKeyId\":76544"),
            sample.replacingOccurrences(of: "https://integral.ru", with: "http://integral.ru"),
            sample.replacingOccurrences(of: "integral.ru", with: "integral.ru.example"),
            sample.replacingOccurrences(of: "01-20-0456", with: "98-76-5432"),
            sample.replacingOccurrences(of: "2026-01-01T12:00:00.000Z", with: "not-a-date"),
            String(decoding: GatewayFixture.notFound, as: UTF8.self).replacingOccurrences(of: "\"data\":null,", with: ""),
            "{}",
        ]
        for fixture in fixtures {
            let sut = CRMGatewayClient(transport: GatewayTransportFake(data: Data(fixture.utf8)))
            await expectError(.invalidResponse) {
                try await sut.customer(forKeyNumber: 76543, configuration: configuration())
            }
        }
    }

    @Test func invalidKeyNeverStartsANetworkRequest() async throws {
        let transport = GatewayTransportFake(data: GatewayFixture.customer)
        let sut = CRMGatewayClient(transport: transport)
        await expectError(.invalidKeyNumber) {
            try await sut.customer(forKeyNumber: 0, configuration: configuration())
        }
        #expect(await transport.requests.isEmpty)
        #expect(CRMKeyNumber.parse("Sign76543") == nil)
        #expect(CRMKeyNumber.parse("76543.0") == nil)
        #expect(CRMKeyNumber.parse("/unexpected/path") == nil)
        #expect(CRMKeyNumber.parse("9007199254740992") == nil)
        #expect(CRMKeyNumber.parse(" 76543 ") == 76543)
    }

    @Test func redirectDelegateAlwaysRefusesTheNewRequest() throws {
        let url = try #require(URL(string: "https://gateway.example/v1/customer-by-key/filter"))
        let task = URLSession.shared.dataTask(with: url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil))
        let newRequest = URLRequest(url: URL(string: "https://other.example")!)
        let refused = Mutex<Bool?>(nil)
        CRMGatewayRedirectBlocker().urlSession(
            URLSession.shared,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: newRequest
        ) { request in
            refused.withLock { $0 = request == nil }
        }
        #expect(refused.withLock { $0 } == true)
        task.cancel()
    }

    private func configuration() throws -> CRMGatewayConfiguration {
        try CRMGatewayConfiguration(origin: "https://gateway.example", token: "fictional-test-token")
    }

    private func expectError(
        _ expected: CRMGatewayError,
        operation: () async throws -> CRMKeyLookupResponse
    ) async {
        do {
            _ = try await operation()
            Issue.record("Expected a gateway error")
        } catch let error as CRMGatewayError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error type")
        }
    }
}

actor GatewayTransportFake: CRMGatewayHTTPTransport {
    let status: Int
    let data: Data
    private(set) var requests: [URLRequest] = []

    init(status: Int = 200, data: Data) {
        self.status = status
        self.data = data
    }

    func send(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

enum GatewayFixture {
    // Deliberately fictional IDs. The displayed organization code differs from its ID.
    static let customer = Data(#"""
    {"data":{"sourceKeyId":76543,"company":{"id":1200456,"name":"Example Company","code":98765432,"formattedCode":"98-76-5432"},"keys":[{"id":76543,"name":"Sample76543","url":"https://integral.ru/personal/keys/01-20-0456/76543/","programs":[{"recordId":7000101,"programId":1000,"name":"  Sample Program  ","version":"4.0","release":"0006","keyUrl":"https://integral.ru/personal/keys/01-20-0456/76543/"},{"recordId":7000102,"programId":1000,"name":"Sample Program","version":"3.2","release":"0010","keyUrl":"https://integral.ru/personal/keys/01-20-0456/76543/"}]},{"id":76544,"name":"Sample76544","url":"https://integral.ru/personal/keys/01-20-0456/76544/","programs":[]}]},"meta":{"requestId":"fictional-request","fetchedAt":"2026-01-01T12:00:00.000Z","complete":true,"fromCache":false}}
    """#.utf8)

    static let notFound = Data(#"""
    {"data":null,"meta":{"requestId":"fictional-missing","fetchedAt":"2026-01-01T12:00:00Z","complete":true,"fromCache":false}}
    """#.utf8)
}
