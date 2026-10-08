//
//  CRMIntegrationRecords.swift
//  Telephone
//

import Foundation

// The gateway contract shared by live lookup, history snapshots and presentation.
// These records describe results; CRM storage, authentication and queries stay on the gateway.

struct CRMKeyLookupCompany: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let formattedCode: String
    // Compatibility/concurrency snapshot supplied by the gateway; never a CRM write target.
    let phone: String?
    let phones: [String]?
    let emails: [String]?

    init(id: Int, name: String, formattedCode: String, phone: String?, phones: [String]?, emails: [String]? = nil) {
        self.id = id
        self.name = name
        self.formattedCode = formattedCode
        self.phone = phone
        self.phones = phones
        self.emails = emails
    }

    func replacingPhone(_ value: String, phones: [String]?) -> Self {
        Self(id: id, name: name, formattedCode: formattedCode, phone: value, phones: phones, emails: emails)
    }

    func containsPhone(_ value: String) -> Bool {
        guard let normalized = CRMPhoneNumber.normalize(value) else { return false }
        if let phones { return phones.contains(normalized) }
        // Compatibility with saved responses from gateways predating canonical phone arrays.
        return CRMPhoneNumber.contains(normalized, in: phone ?? "")
    }
}

struct CRMKeyLookupProgram: Codable, Equatable, Identifiable, Sendable {
    let recordId: Int
    let programId: Int?
    let name: String
    let version: String?
    let release: String?
    let keyUrl: URL
    var id: Int { recordId }
}

struct CRMKeyLookupKey: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let url: URL
    let programs: [CRMKeyLookupProgram]
}

struct CRMKeyLookupCustomer: Codable, Equatable, Sendable {
    let sourceKeyId: Int?
    let company: CRMKeyLookupCompany
    let keys: [CRMKeyLookupKey]
}

struct CRMKeyLookupMetadata: Codable, Equatable, Sendable {
    let requestId: String
    let fetchedAt: String
    let complete: Bool
    let fromCache: Bool
}

struct CRMKeyLookupResponse: Decodable, Equatable, Sendable {
    let data: CRMKeyLookupCustomer?
    let meta: CRMKeyLookupMetadata

    init(data: CRMKeyLookupCustomer?, meta: CRMKeyLookupMetadata) {
        self.data = data
        self.meta = meta
    }

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

struct CRMPhoneLookupMatch: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let formattedCode: String
}

struct CRMPhoneLookupResponse: Decodable, Equatable, Sendable {
    let data: CRMKeyLookupCustomer?
    let matches: [CRMPhoneLookupMatch]
    let meta: CRMKeyLookupMetadata

    private enum CodingKeys: String, CodingKey { case data, matches, meta }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.data) else {
            throw DecodingError.keyNotFound(
                CodingKeys.data,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing gateway data field")
            )
        }
        data = try container.decodeIfPresent(CRMKeyLookupCustomer.self, forKey: .data)
        matches = try container.decode([CRMPhoneLookupMatch].self, forKey: .matches)
        meta = try container.decode(CRMKeyLookupMetadata.self, forKey: .meta)
    }
}

struct CRMPhoneAppendData: Decodable, Equatable, Sendable {
    let companyId: Int
    let phone: String
    let phones: [String]?
    let added: Bool
}

struct CRMPhoneAppendResponse: Decodable, Equatable, Sendable {
    let data: CRMPhoneAppendData
    let meta: CRMKeyLookupMetadata
}

protocol CRMKeyLookupProvider: Sendable {
    func customer(
        forEmail email: String,
        companyID: Int?,
        configuration: CRMGatewayConfiguration
    ) async throws -> CRMPhoneLookupResponse

    func customer(
        forKeyNumber keyNumber: Int,
        configuration: CRMGatewayConfiguration
    ) async throws -> CRMKeyLookupResponse

    func customer(
        forPhoneNumber phoneNumber: String,
        companyID: Int?,
        configuration: CRMGatewayConfiguration
    ) async throws -> CRMPhoneLookupResponse

    func appendPhone(
        _ phoneNumber: String,
        companyID: Int,
        sourceKeyID: Int,
        expectedPhone: String,
        configuration: CRMGatewayConfiguration
    ) async throws -> CRMPhoneAppendResponse
}

extension CRMKeyLookupProvider {
    func customer(
        forEmail email: String,
        companyID: Int?,
        configuration: CRMGatewayConfiguration
    ) async throws -> CRMPhoneLookupResponse {
        throw CRMGatewayError.invalidResponse
    }

    func customer(
        forPhoneNumber phoneNumber: String,
        companyID: Int?,
        configuration: CRMGatewayConfiguration
    ) async throws -> CRMPhoneLookupResponse {
        throw CRMGatewayError.unavailable
    }

    func appendPhone(
        _ phoneNumber: String,
        companyID: Int,
        sourceKeyID: Int,
        expectedPhone: String,
        configuration: CRMGatewayConfiguration
    ) async throws -> CRMPhoneAppendResponse {
        throw CRMGatewayError.forbidden
    }
}

/// Navigation allowlist for gateway-supplied links, not a company-code formatter.
enum CRMKeyPortalURL {
    static func organizationSegment(in url: URL, keyID: Int) -> String? {
        guard CRMKeyNumber.isValid(keyID),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == "integral.ru",
              components.port == nil, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.percentEncodedPath == components.path,
              url.absoluteString == "https://integral.ru" + components.path else {
            return nil
        }
        let path = components.path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.count == 6, path[0].isEmpty, path[1] == "personal", path[2] == "keys",
              path[4] == String(keyID), path[5].isEmpty else { return nil }
        let segment = String(path[3])
        // The organization segment is opaque; its relationship to company.id is
        // established by the gateway. Accept legacy short decimal-hyphen segments.
        guard !segment.isEmpty, segment.utf8.count <= 64,
              segment.utf8.first.map({ (48...57).contains($0) }) == true,
              segment.utf8.allSatisfy({ (48...57).contains($0) || $0 == 45 }),
              segment.split(separator: "-", omittingEmptySubsequences: false).count == 3 else {
            return nil
        }
        return segment
    }
}



protocol CRMGatewayStatusProvider: Sendable {
    func runtime(configuration: CRMGatewayConfiguration) async throws -> CRMGatewayRuntime
}

struct CRMGatewayStatusResponse: Decodable, Sendable { let runtime: CRMGatewayRuntime }

/// Exact POST /v1/status contract, pinned to gateway 30a523a.
/// This identifies the running process; it makes no claim about the latest release.
struct CRMGatewayRuntime: Decodable, Equatable, Sendable {
    struct Build: Decodable, Equatable, Sendable {
        let version: String?
        let commit: String?
        let builtAt: String?
        let integrity: String

        private enum CodingKeys: String, CodingKey { case version, commit, builtAt, integrity }
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Nullable fields are required by the contract: missing is not unknown.
            version = try container.decode(String?.self, forKey: .version)
            commit = try container.decode(String?.self, forKey: .commit)
            builtAt = try container.decode(String?.self, forKey: .builtAt)
            integrity = try container.decode(String.self, forKey: .integrity)
        }
    }
    let build: Build
    let startedAt: String
    let processId: Int

    func validate() throws {
        guard processId > 0, Self.date(startedAt) != nil else { throw CRMGatewayError.invalidResponse }
        switch build.integrity {
        case "unknown":
            guard build.version == nil, build.commit == nil, build.builtAt == nil else { throw CRMGatewayError.invalidResponse }
        case "verified":
            guard let version = build.version,
                  !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let commit = build.commit, commit.range(of: #"^[a-f0-9]{40}$"#, options: .regularExpression) != nil,
                  let builtAt = build.builtAt, Self.date(builtAt) != nil else { throw CRMGatewayError.invalidResponse }
        default: throw CRMGatewayError.invalidResponse
        }
    }

    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
