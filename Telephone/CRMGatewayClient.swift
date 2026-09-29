//
//  CRMGatewayClient.swift
//  Telephone
//

import Foundation

enum CRMGatewayError: Error, Equatable, Sendable {
    case disabled
    case invalidOrigin
    case missingToken
    case invalidKeyNumber
    case unauthorized
    case unavailable
    case rateLimited
    case redirectDenied
    case invalidResponse
    case keychain
}

struct CRMGatewayConfiguration: Equatable, Sendable {
    let origin: URL
    let token: String

    init(origin: String, token: String) throws {
        self.origin = try Self.canonicalOrigin(origin)
        guard !token.isEmpty, token.utf8.count <= 4096,
              token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
            throw CRMGatewayError.missingToken
        }
        self.token = token
    }

    static func canonicalOrigin(_ value: String) throws -> URL {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              components.port.map({ (1...65535).contains($0) }) ?? true else {
            throw CRMGatewayError.invalidOrigin
        }
        components.scheme = "https"
        components.host = host.lowercased()
        components.path = ""
        if components.port == 443 { components.port = nil }
        guard let url = components.url else {
            throw CRMGatewayError.invalidOrigin
        }
        return url
    }
}

struct CRMKeyLookupCompany: Decodable, Equatable, Sendable {
    let id: Int
    let name: String
    let formattedCode: String
}

struct CRMKeyLookupProgram: Decodable, Equatable, Identifiable, Sendable {
    let recordId: Int
    let programId: Int?
    let name: String
    let version: String?
    let release: String?
    let keyUrl: URL
    var id: Int { recordId }
}

struct CRMKeyLookupKey: Decodable, Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let url: URL
    let programs: [CRMKeyLookupProgram]
}

struct CRMKeyLookupCustomer: Decodable, Equatable, Sendable {
    let sourceKeyId: Int
    let company: CRMKeyLookupCompany
    let keys: [CRMKeyLookupKey]
}

struct CRMKeyLookupMetadata: Decodable, Equatable, Sendable {
    let requestId: String
    let fetchedAt: String
    let complete: Bool
    let fromCache: Bool
}

struct CRMKeyLookupResponse: Decodable, Equatable, Sendable {
    let data: CRMKeyLookupCustomer?
    let meta: CRMKeyLookupMetadata

    private enum CodingKeys: String, CodingKey { case data, meta }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.data) else {
            throw DecodingError.keyNotFound(
                CodingKeys.data,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing gateway data field")
            )
        }
        data = try container.decodeIfPresent(CRMKeyLookupCustomer.self, forKey: .data)
        meta = try container.decode(CRMKeyLookupMetadata.self, forKey: .meta)
    }
}

protocol CRMKeyLookupProvider: Sendable {
    func customer(
        forKeyNumber keyNumber: Int,
        configuration: CRMGatewayConfiguration
    ) async throws -> CRMKeyLookupResponse
}

protocol CRMGatewayHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class CRMGatewayRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

final class CRMGatewayURLSessionTransport: CRMGatewayHTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 65
        configuration.timeoutIntervalForResource = 70
        session = URLSession(
            configuration: configuration,
            delegate: CRMGatewayRedirectBlocker(),
            delegateQueue: nil
        )
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CRMGatewayError.invalidResponse
        }
        return (data, response)
    }
}

actor CRMGatewayClient: CRMKeyLookupProvider {
    private let transport: any CRMGatewayHTTPTransport

    init(transport: any CRMGatewayHTTPTransport = CRMGatewayURLSessionTransport()) {
        self.transport = transport
    }

    func customer(
        forKeyNumber keyNumber: Int,
        configuration: CRMGatewayConfiguration
    ) async throws -> CRMKeyLookupResponse {
        guard CRMKeyNumber.isValid(keyNumber) else {
            throw CRMGatewayError.invalidKeyNumber
        }
        try Task.checkCancellation()
        let endpoint = configuration.origin.appendingPathComponent(
            "v1/customer-by-key/filter"
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Bearer \(configuration.token)",
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try JSONEncoder().encode(KeyNumberRequest(keyNumber: keyNumber))

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as CRMGatewayError {
            throw error
        } catch {
            throw CRMGatewayError.unavailable
        }
        try Task.checkCancellation()
        switch response.statusCode {
        case 200: break
        case 301...399: throw CRMGatewayError.redirectDenied
        case 401, 403: throw CRMGatewayError.unauthorized
        case 429: throw CRMGatewayError.rateLimited
        case 500...599: throw CRMGatewayError.unavailable
        default: throw CRMGatewayError.invalidResponse
        }
        // A gateway must return the original endpoint, never an alternate origin.
        guard response.url == endpoint, data.count <= 16 * 1024 * 1024 else {
            throw CRMGatewayError.invalidResponse
        }
        let result: CRMKeyLookupResponse
        do {
            result = try JSONDecoder().decode(CRMKeyLookupResponse.self, from: data)
        } catch {
            throw CRMGatewayError.invalidResponse
        }
        try Self.validate(result, keyNumber: keyNumber)
        return result
    }

    private static func validate(_ result: CRMKeyLookupResponse, keyNumber: Int) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let validDate = formatter.date(from: result.meta.fetchedAt) != nil
        formatter.formatOptions = [.withInternetDateTime]
        guard result.meta.complete,
              !result.meta.requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              validDate || formatter.date(from: result.meta.fetchedAt) != nil else {
            throw CRMGatewayError.invalidResponse
        }
        guard let customer = result.data else { return }
        guard customer.sourceKeyId == keyNumber,
              CRMKeyNumber.isValid(customer.company.id),
              !customer.company.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(customer.keys.map(\.id)).count == customer.keys.count,
              customer.keys.contains(where: { $0.id == keyNumber }) else {
            throw CRMGatewayError.invalidResponse
        }
        for key in customer.keys {
            guard CRMKeyNumber.isValid(key.id),
                  let expectedURL = CRMKeyPortalURL.make(companyID: customer.company.id, keyID: key.id),
                  key.url.absoluteString == expectedURL.absoluteString,
                  Set(key.programs.map(\.recordId)).count == key.programs.count else {
                throw CRMGatewayError.invalidResponse
            }
            for program in key.programs {
                guard CRMKeyNumber.isValid(program.recordId),
                      program.programId.map(CRMKeyNumber.isValid) ?? true,
                      program.keyUrl.absoluteString == expectedURL.absoluteString else {
                    throw CRMGatewayError.invalidResponse
                }
            }
        }
    }
}

private struct KeyNumberRequest: Encodable {
    let keyNumber: Int
}

enum CRMKeyNumber {
    // JSON numbers are also consumed by JavaScript on the gateway.
    static func isValid(_ value: Int) -> Bool {
        value > 0 && value <= 9_007_199_254_740_991
    }

    static func parse(_ value: String) -> Int? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(value), isValid(number) else { return nil }
        return number
    }
}

enum CRMKeyPortalURL {
    static func make(companyID: Int, keyID: Int) -> URL? {
        guard CRMKeyNumber.isValid(companyID), CRMKeyNumber.isValid(keyID) else {
            return nil
        }
        // Reproduce the portal path formatter used by the CRM client exactly.
        var digits = Array(String(companyID))
        if digits.count < 8 { digits.insert("0", at: 0) }
        digits.insert("-", at: min(4, digits.count))
        digits.insert("-", at: min(2, digits.count))
        return URL(string: "https://integral.ru/personal/keys/\(String(digits))/\(keyID)/")
    }
}
