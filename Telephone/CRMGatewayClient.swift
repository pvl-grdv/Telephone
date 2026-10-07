//
//  CRMGatewayClient.swift
//  Telephone
//

import Foundation

enum CRMGatewayError: String, Error, Equatable, Sendable, Codable {
    case disabled
    case invalidOrigin
    case missingToken
    case invalidKeyNumber
    case invalidPhoneNumber
    case invalidEmail
    case forbidden
    case conflict
    case phoneWriteUnconfirmed
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

    init(origin: String, token: String, allowTailscaleHTTP: Bool = false) throws {
        self.origin = try Self.canonicalOrigin(origin, allowTailscaleHTTP: allowTailscaleHTTP)
        guard !token.isEmpty, token.utf8.count <= 4096,
              token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
            throw CRMGatewayError.missingToken
        }
        self.token = token
    }

    static func canonicalOrigin(_ value: String, allowTailscaleHTTP: Bool = false) throws -> URL {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && allowTailscaleHTTP),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              components.port.map({ (1...65535).contains($0) }) ?? true else {
            throw CRMGatewayError.invalidOrigin
        }
        if scheme == "http" {
            // Keep the ATS exception useful only for explicit Tailscale IPv4 origins.
            // Checking the raw URL prevents URL parsing from accepting alternate IP spellings.
            guard value.range(
                of: #"^http://[0-9.]+:[0-9]{1,5}/?$"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil,
                  let rawHost = value.dropFirst(7).split(separator: ":", omittingEmptySubsequences: false).first,
                  String(rawHost) == host,
                  let port = components.port, (1...65535).contains(port),
                  Self.isTailscaleIPv4(host) else {
                throw CRMGatewayError.invalidOrigin
            }
        }
        components.scheme = scheme
        components.host = host.lowercased()
        components.path = ""
        if scheme == "https", components.port == 443 { components.port = nil }
        guard let url = components.url else {
            throw CRMGatewayError.invalidOrigin
        }
        return url
    }

    private static func isTailscaleIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        var values: [Int] = []
        for octet in octets {
            guard !octet.isEmpty, octet.count <= 3,
                  (octet.count == 1 || octet.first != "0"),
                  octet.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(octet), number <= 255 else { return false }
            values.append(number)
        }
        return values[0] == 100 && (64...127).contains(values[1])
    }
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
        forEmail email: String,
        companyID: Int?,
        configuration: CRMGatewayConfiguration
    ) async throws -> CRMPhoneLookupResponse {
        guard let email = CRMEmailAddress.normalize(email) else { throw CRMGatewayError.invalidEmail }
        if let companyID, !CRMKeyNumber.isValid(companyID) { throw CRMGatewayError.invalidResponse }
        let result: CRMPhoneLookupResponse = try await send(
            route: .emailLookup, body: EmailRequest(email: email, companyId: companyID), configuration: configuration
        )
        try Self.validateMetadata(result.meta)
        guard Set(result.matches.map(\.id)).count == result.matches.count,
              result.matches.allSatisfy({ CRMKeyNumber.isValid($0.id)
                  && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw CRMGatewayError.invalidResponse
        }
        if let customer = result.data {
            guard customer.sourceKeyId == nil,
                  result.matches.contains(where: { $0.id == customer.company.id }),
                  customer.company.emails?.contains(email) == true,
                  companyID.map({ $0 == customer.company.id }) ?? (result.matches.count == 1) else {
                throw CRMGatewayError.invalidResponse
            }
            try Self.validateCustomer(customer)
        } else if result.matches.count == 1 || companyID != nil {
            throw CRMGatewayError.invalidResponse
        }
        return result
    }

    func customer(
        forKeyNumber keyNumber: Int,
        configuration: CRMGatewayConfiguration
    ) async throws -> CRMKeyLookupResponse {
        guard CRMKeyNumber.isValid(keyNumber) else {
            throw CRMGatewayError.invalidKeyNumber
        }
        let result: CRMKeyLookupResponse = try await send(
            route: .keyLookup,
            body: KeyNumberRequest(keyNumber: keyNumber),
            configuration: configuration
        )
        try Self.validateMetadata(result.meta)
        if let customer = result.data {
            guard customer.sourceKeyId == keyNumber,
                  customer.keys.contains(where: { $0.id == keyNumber }) else {
                throw CRMGatewayError.invalidResponse
            }
            try Self.validateCustomer(customer)
        }
        return result
    }

    func customer(
        forPhoneNumber phoneNumber: String,
        companyID: Int?,
        configuration: CRMGatewayConfiguration
    ) async throws -> CRMPhoneLookupResponse {
        guard let phone = CRMPhoneNumber.normalize(phoneNumber) else {
            throw CRMGatewayError.invalidPhoneNumber
        }
        if let companyID, !CRMKeyNumber.isValid(companyID) {
            throw CRMGatewayError.invalidResponse
        }
        let result: CRMPhoneLookupResponse = try await send(
            route: .phoneLookup,
            body: PhoneNumberRequest(phoneNumber: phone, companyId: companyID),
            configuration: configuration
        )
        try Self.validateMetadata(result.meta)
        guard Set(result.matches.map(\.id)).count == result.matches.count,
              result.matches.allSatisfy({
                  CRMKeyNumber.isValid($0.id)
                      && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            throw CRMGatewayError.invalidResponse
        }
        if let customer = result.data {
            guard customer.sourceKeyId == nil,
                  result.matches.contains(where: { $0.id == customer.company.id }),
                  customer.company.phones.map({ $0.contains(phone) }) ?? true,
                  companyID.map({ $0 == customer.company.id }) ?? (result.matches.count == 1) else {
                throw CRMGatewayError.invalidResponse
            }
            try Self.validateCustomer(customer)
        } else if result.matches.count == 1 || companyID != nil {
            // Exactly one match/explicit selection must include its complete inventory.
            throw CRMGatewayError.invalidResponse
        }
        return result
    }

    func appendPhone(
        _ phoneNumber: String,
        companyID: Int,
        sourceKeyID: Int,
        expectedPhone: String,
        configuration: CRMGatewayConfiguration
    ) async throws -> CRMPhoneAppendResponse {
        guard let phone = CRMPhoneNumber.normalize(phoneNumber) else {
            throw CRMGatewayError.invalidPhoneNumber
        }
        guard CRMKeyNumber.isValid(companyID), CRMKeyNumber.isValid(sourceKeyID) else {
            throw CRMGatewayError.invalidKeyNumber
        }
        let result: CRMPhoneAppendResponse = try await send(
            route: .phoneAppend,
            body: PhoneAppendRequest(
                companyId: companyID, sourceKeyId: sourceKeyID,
                phoneNumber: phone, expectedPhone: expectedPhone
            ),
            configuration: configuration
        )
        try Self.validateMetadata(result.meta)
        try Self.validatePhones(result.data.phones)
        guard result.data.companyId == companyID,
              result.data.phones.map({ $0.contains(phone) })
                ?? (!result.data.added || CRMPhoneNumber.contains(phone, in: result.data.phone)) else {
            throw CRMGatewayError.invalidResponse
        }
        return result
    }

    private func send<Request: Encodable, Response: Decodable>(
        route: GatewayRoute,
        body: Request,
        configuration: CRMGatewayConfiguration
    ) async throws -> Response {
        try Task.checkCancellation()
        let endpoint = configuration.origin.appendingPathComponent(route.rawValue)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Bearer \(configuration.token)",
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            if route == .phoneAppend, !Task.isCancelled { throw CRMGatewayError.phoneWriteUnconfirmed }
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            if route == .phoneAppend, !Task.isCancelled { throw CRMGatewayError.phoneWriteUnconfirmed }
            throw CancellationError()
        } catch let error as CRMGatewayError {
            if route == .phoneAppend { throw CRMGatewayError.phoneWriteUnconfirmed }
            throw error
        } catch {
            throw route == .phoneAppend ? CRMGatewayError.phoneWriteUnconfirmed : .unavailable
        }
        try Task.checkCancellation()
        switch response.statusCode {
        case 200: break
        case 301...399: throw CRMGatewayError.redirectDenied
        case 401: throw CRMGatewayError.unauthorized
        case 403: throw route == .phoneAppend ? CRMGatewayError.forbidden : .unauthorized
        case 409: throw route == .phoneAppend ? CRMGatewayError.conflict : .invalidResponse
        case 429: throw CRMGatewayError.rateLimited
        case 500...599:
            if route == .phoneAppend, Self.errorCode(in: data) == "PHONE_WRITE_UNCONFIRMED" {
                throw CRMGatewayError.phoneWriteUnconfirmed
            }
            throw CRMGatewayError.unavailable
        default: throw CRMGatewayError.invalidResponse
        }
        // A gateway must return the original endpoint, never an alternate origin.
        guard response.url == endpoint, data.count <= 16 * 1024 * 1024 else {
            throw CRMGatewayError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw route == .phoneAppend ? CRMGatewayError.phoneWriteUnconfirmed : .invalidResponse
        }
    }

    private static func errorCode(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object["error"] as? [String: Any])?["code"] as? String
            ?? object["code"] as? String
    }

    private static func validateMetadata(_ meta: CRMKeyLookupMetadata) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let validDate = formatter.date(from: meta.fetchedAt) != nil
        formatter.formatOptions = [.withInternetDateTime]
        guard meta.complete,
              !meta.requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              validDate || formatter.date(from: meta.fetchedAt) != nil else {
            throw CRMGatewayError.invalidResponse
        }
    }

    private static func validateCustomer(_ customer: CRMKeyLookupCustomer) throws {
        try validatePhones(customer.company.phones)
        if let emails = customer.company.emails {
            guard Set(emails).count == emails.count,
                  emails.allSatisfy({ CRMEmailAddress.normalize($0) == $0 }) else {
                throw CRMGatewayError.invalidResponse
            }
        }
        guard CRMKeyNumber.isValid(customer.company.id),
              !customer.company.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(customer.keys.map(\.id)).count == customer.keys.count else {
            throw CRMGatewayError.invalidResponse
        }
        var organizationSegment: String?
        for key in customer.keys {
            guard CRMKeyNumber.isValid(key.id),
                  let segment = CRMKeyPortalURL.organizationSegment(in: key.url, keyID: key.id),
                  organizationSegment.map({ $0 == segment }) ?? true,
                  Set(key.programs.map(\.recordId)).count == key.programs.count else {
                throw CRMGatewayError.invalidResponse
            }
            organizationSegment = segment
            for program in key.programs {
                guard CRMKeyNumber.isValid(program.recordId),
                      program.programId.map(CRMKeyNumber.isValid) ?? true,
                      program.keyUrl.absoluteString == key.url.absoluteString else {
                    throw CRMGatewayError.invalidResponse
                }
            }
        }
    }

    private static func validatePhones(_ phones: [String]?) throws {
        guard let phones else { return }
        guard Set(phones).count == phones.count,
              phones.allSatisfy({ CRMPhoneNumber.normalize($0) == $0 }) else {
            throw CRMGatewayError.invalidResponse
        }
    }
}

private struct KeyNumberRequest: Encodable {
    let keyNumber: Int
}

private struct PhoneNumberRequest: Encodable {
    let phoneNumber: String
    let companyId: Int?
}

private struct EmailRequest: Encodable {
    let email: String
    let companyId: Int?
}

private struct PhoneAppendRequest: Encodable {
    let companyId: Int
    let sourceKeyId: Int
    let phoneNumber: String
    let expectedPhone: String
}

private enum GatewayRoute: String {
    case keyLookup = "v1/customer-by-key/filter"
    case phoneLookup = "v1/customer-by-phone/filter"
    case emailLookup = "v1/customer-by-email/filter"
    case phoneAppend = "v1/customer-phone/append"
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
