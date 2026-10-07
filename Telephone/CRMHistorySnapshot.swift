//
//  CRMHistorySnapshot.swift
//  Telephone
//

import Foundation

enum CRMHistoryCheckStatus: String, Codable, Equatable, Sendable {
    case matched
    case notFound
    case ambiguous
    case failed
}

enum CRMHistorySnapshotError: Error, Equatable {
    case invalidSnapshot
}

enum CRMHistoryLookupIdentity: Codable, Equatable, Sendable {
    case phone(String)
    case key(Int)
    case email(String)

    private enum CodingKeys: String, CodingKey { case kind, value }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(String.self, forKey: .value)
        switch try container.decode(String.self, forKey: .kind) {
        case "phone": self = .phone(value)
        case "key":
            guard let key = CRMKeyNumber.parse(value), String(key) == value else {
                throw CRMHistorySnapshotError.invalidSnapshot
            }
            self = .key(key)
        case "email": self = .email(value)
        default: throw CRMHistorySnapshotError.invalidSnapshot
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .phone(let phone):
            try container.encode("phone", forKey: .kind)
            try container.encode(phone, forKey: .value)
        case .key(let key):
            try container.encode("key", forKey: .kind)
            try container.encode(String(key), forKey: .value)
        case .email(let email):
            try container.encode("email", forKey: .kind)
            try container.encode(email, forKey: .value)
        }
    }
}

struct CRMHistorySnapshot: Codable, Equatable, Sendable {
    static let maximumJSONBytes = 16 * 1024 * 1024
    let schemaVersion: Int
    let checkedAt: Date
    let status: CRMHistoryCheckStatus
    // The actual caller stays separate from a manual organization lookup.
    let phone: String?
    let lookupIdentity: CRMHistoryLookupIdentity?
    let customer: CRMKeyLookupCustomer?
    let matches: [CRMPhoneLookupMatch]
    let errorCode: CRMGatewayError?
    let metadata: CRMKeyLookupMetadata?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, checkedAt, status, phone, customer, matches, errorCode, metadata
        case lookupIdentity = "lookup"
    }

    static func checked(
        response: CRMPhoneLookupResponse,
        phone: String,
        checkedAt: Date,
        selectedCompanyID: Int? = nil
    ) throws -> Self {
        guard CRMPhoneNumber.normalize(phone) == phone else {
            throw CRMGatewayError.invalidResponse
        }
        return try checkedContact(
            response: response, lookup: .phone(phone), phone: phone,
            checkedAt: checkedAt, selectedCompanyID: selectedCompanyID
        )
    }

    static func checkedKey(
        response: CRMKeyLookupResponse,
        keyNumber: Int,
        phone: String?,
        checkedAt: Date
    ) throws -> Self {
        guard CRMKeyNumber.isValid(keyNumber), response.meta.complete,
              phone.map({ CRMPhoneNumber.normalize($0) == $0 }) ?? true else {
            throw CRMGatewayError.invalidResponse
        }
        let customer = try response.data.map {
            try normalizedCustomer($0, expectedSourceKey: keyNumber)
        }
        let snapshot = Self(
            schemaVersion: 2, checkedAt: canonicalTimestamp(checkedAt),
            status: customer == nil ? .notFound : .matched,
            phone: phone, lookupIdentity: .key(keyNumber), customer: customer,
            matches: [], errorCode: nil, metadata: response.meta
        )
        try snapshot.validate()
        return snapshot
    }

    static func checkedEmail(
        response: CRMPhoneLookupResponse,
        email: String,
        phone: String?,
        checkedAt: Date,
        selectedCompanyID: Int? = nil
    ) throws -> Self {
        guard let canonical = CRMEmailAddress.normalize(email),
              phone.map({ CRMPhoneNumber.normalize($0) == $0 }) ?? true else {
            throw CRMGatewayError.invalidResponse
        }
        return try checkedContact(
            response: response, lookup: .email(canonical), phone: phone,
            checkedAt: checkedAt, selectedCompanyID: selectedCompanyID
        )
    }

    static func failed(
        phone: String?, error: CRMGatewayError, checkedAt: Date,
        lookupIdentity: CRMHistoryLookupIdentity? = nil
    ) -> Self {
        Self(schemaVersion: 2, checkedAt: canonicalTimestamp(checkedAt), status: .failed,
             phone: phone, lookupIdentity: lookupIdentity ?? phone.map(CRMHistoryLookupIdentity.phone),
             customer: nil, matches: [], errorCode: error, metadata: nil)
    }

    func storedCheck() throws -> StoredCallCRMCheck {
        try validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumJSONBytes,
              let json = String(data: data, encoding: .utf8) else {
            throw CRMHistorySnapshotError.invalidSnapshot
        }
        return StoredCallCRMCheck(
            checkedAt: checkedAt, status: status.rawValue,
            companyID: customer?.company.id, companyName: customer?.company.name,
            snapshotJSON: json
        )
    }

    static func restored(from check: StoredCallCRMCheck) throws -> Self {
        guard let data = check.snapshotJSON.data(using: .utf8), data.count <= maximumJSONBytes else {
            throw CRMHistorySnapshotError.invalidSnapshot
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot = try decoder.decode(Self.self, from: data)
        try snapshot.validate()
        guard abs(snapshot.checkedAt.timeIntervalSince(check.checkedAt)) < 0.001,
              snapshot.status.rawValue == check.status,
              snapshot.customer?.company.id == check.companyID,
              snapshot.customer?.company.name == check.companyName else {
            throw CRMHistorySnapshotError.invalidSnapshot
        }
        return snapshot
    }

    private static func checkedContact(
        response: CRMPhoneLookupResponse,
        lookup: CRMHistoryLookupIdentity,
        phone: String?,
        checkedAt: Date,
        selectedCompanyID: Int?
    ) throws -> Self {
        guard response.meta.complete else { throw CRMGatewayError.invalidResponse }
        let matches = try response.matches.map { match in
            guard CRMKeyNumber.isValid(match.id), !trim(match.name).isEmpty else {
                throw CRMGatewayError.invalidResponse
            }
            return CRMPhoneLookupMatch(id: match.id, name: trim(match.name), formattedCode: trim(match.formattedCode))
        }
        guard Set(matches.map(\.id)).count == matches.count else {
            throw CRMGatewayError.invalidResponse
        }
        let matchedPhone: String?
        if case .phone(let value) = lookup { matchedPhone = value } else { matchedPhone = nil }
        let customer = try response.data.map {
            try normalizedCustomer($0, matchedPhone: matchedPhone)
        }
        if let customer {
            guard matches.contains(where: { $0.id == customer.company.id }),
                  selectedCompanyID.map({ $0 == customer.company.id }) ?? (matches.count == 1),
                  matchesLookup(customer, lookup: lookup) else {
                throw CRMGatewayError.invalidResponse
            }
        } else if matches.count == 1 || selectedCompanyID != nil {
            throw CRMGatewayError.invalidResponse
        }
        let snapshot = Self(
            schemaVersion: 2, checkedAt: canonicalTimestamp(checkedAt),
            status: customer != nil ? .matched : matches.isEmpty ? .notFound : .ambiguous,
            phone: phone, lookupIdentity: lookup, customer: customer, matches: matches,
            errorCode: nil, metadata: response.meta
        )
        try snapshot.validate()
        return snapshot
    }

    private func validate() throws {
        guard (1...2).contains(schemaVersion), checkedAt.timeIntervalSince1970.isFinite,
              phone.map({ CRMPhoneNumber.normalize($0) == $0 }) ?? true,
              Set(matches.map(\.id)).count == matches.count,
              matches.allSatisfy({ CRMKeyNumber.isValid($0.id) && !Self.trim($0.name).isEmpty }) else {
            throw CRMHistorySnapshotError.invalidSnapshot
        }
        if let lookupIdentity {
            switch lookupIdentity {
            case .phone(let value):
                guard CRMPhoneNumber.normalize(value) == value, value == phone else {
                    throw CRMHistorySnapshotError.invalidSnapshot
                }
            case .key(let value):
                guard schemaVersion == 2, CRMKeyNumber.isValid(value) else {
                    throw CRMHistorySnapshotError.invalidSnapshot
                }
            case .email(let value):
                guard schemaVersion == 2, CRMEmailAddress.normalize(value) == value else {
                    throw CRMHistorySnapshotError.invalidSnapshot
                }
            }
        } else if status != .failed {
            throw CRMHistorySnapshotError.invalidSnapshot
        }
        switch status {
        case .matched:
            guard let customer, let lookupIdentity, errorCode == nil,
                  Self.matchesLookup(customer, lookup: lookupIdentity) else {
                throw CRMHistorySnapshotError.invalidSnapshot
            }
            let expectedKey: Int?
            if case .key(let key) = lookupIdentity {
                expectedKey = key
                guard matches.isEmpty else { throw CRMHistorySnapshotError.invalidSnapshot }
            } else {
                expectedKey = nil
                guard matches.contains(where: { $0.id == customer.company.id }) else {
                    throw CRMHistorySnapshotError.invalidSnapshot
                }
            }
            guard try Self.normalizedCustomer(customer, expectedSourceKey: expectedKey) == customer else {
                throw CRMHistorySnapshotError.invalidSnapshot
            }
        case .notFound:
            guard customer == nil, matches.isEmpty, errorCode == nil else {
                throw CRMHistorySnapshotError.invalidSnapshot
            }
        case .ambiguous:
            guard customer == nil, matches.count > 1, errorCode == nil else {
                throw CRMHistorySnapshotError.invalidSnapshot
            }
            if let lookupIdentity, case .key = lookupIdentity {
                throw CRMHistorySnapshotError.invalidSnapshot
            }
        case .failed:
            guard customer == nil, matches.isEmpty, errorCode != nil, metadata == nil else {
                throw CRMHistorySnapshotError.invalidSnapshot
            }
        }
        if status != .failed {
            guard let metadata, metadata.complete,
                  !Self.trim(metadata.requestId).isEmpty else {
                throw CRMHistorySnapshotError.invalidSnapshot
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let withFractions = formatter.date(from: metadata.fetchedAt)
            formatter.formatOptions = [.withInternetDateTime]
            guard withFractions != nil || formatter.date(from: metadata.fetchedAt) != nil else {
                throw CRMHistorySnapshotError.invalidSnapshot
            }
        }
    }

    private static func matchesLookup(
        _ customer: CRMKeyLookupCustomer, lookup: CRMHistoryLookupIdentity
    ) -> Bool {
        switch lookup {
        case .phone(let phone): return customer.company.phones?.contains(phone) == true
        case .email(let email): return customer.company.emails?.contains(email) == true
        case .key(let key):
            return customer.sourceKeyId == key && customer.keys.contains(where: { $0.id == key })
        }
    }

    private static func normalizedCustomer(
        _ customer: CRMKeyLookupCustomer,
        matchedPhone: String? = nil,
        expectedSourceKey: Int? = nil
    ) throws -> CRMKeyLookupCustomer {
        guard customer.sourceKeyId == expectedSourceKey, CRMKeyNumber.isValid(customer.company.id),
              !trim(customer.company.name).isEmpty,
              expectedSourceKey.map({ key in customer.keys.contains(where: { $0.id == key }) }) ?? true,
              Set(customer.keys.map(\.id)).count == customer.keys.count else {
            throw CRMGatewayError.invalidResponse
        }
        let phones: [String]
        if let canonical = customer.company.phones {
            guard Set(canonical).count == canonical.count,
                  canonical.allSatisfy({ CRMPhoneNumber.normalize($0) == $0 }) else {
                throw CRMGatewayError.invalidResponse
            }
            phones = canonical
        } else {
            var seen = Set<String>()
            var legacyPhones = (customer.company.phone ?? "")
                .components(separatedBy: CharacterSet(charactersIn: ",;\n\r"))
                .compactMap(CRMPhoneNumber.normalize)
                .filter { seen.insert($0).inserted }
            // Only a validated legacy phone lookup may supply a missing caller identity.
            if let matchedPhone, seen.insert(matchedPhone).inserted {
                legacyPhones.append(matchedPhone)
            }
            phones = legacyPhones
        }
        if let emails = customer.company.emails {
            guard Set(emails).count == emails.count,
                  emails.allSatisfy({ CRMEmailAddress.normalize($0) == $0 }) else {
                throw CRMGatewayError.invalidResponse
            }
        }
        let company = CRMKeyLookupCompany(
            id: customer.company.id, name: trim(customer.company.name),
            formattedCode: trim(customer.company.formattedCode), phone: nil, phones: phones,
            emails: customer.company.emails
        )
        var organizationSegment: String?
        let keys = try customer.keys.map { key in
            guard CRMKeyNumber.isValid(key.id),
                  let segment = CRMKeyPortalURL.organizationSegment(in: key.url, keyID: key.id),
                  organizationSegment.map({ $0 == segment }) ?? true,
                  Set(key.programs.map(\.recordId)).count == key.programs.count else {
                throw CRMGatewayError.invalidResponse
            }
            organizationSegment = segment
            let url = key.url
            let programs = try key.programs.map { program in
                guard CRMKeyNumber.isValid(program.recordId),
                      program.programId.map(CRMKeyNumber.isValid) ?? true,
                      program.keyUrl.absoluteString == url.absoluteString else {
                    throw CRMGatewayError.invalidResponse
                }
                return CRMKeyLookupProgram(
                    recordId: program.recordId, programId: program.programId,
                    name: trim(program.name), version: program.version, release: program.release,
                    keyUrl: url
                )
            }
            return CRMKeyLookupKey(id: key.id, name: trim(key.name), url: url, programs: programs)
        }
        return CRMKeyLookupCustomer(sourceKeyId: expectedSourceKey, company: company, keys: keys)
    }

    private static func canonicalTimestamp(_ value: Date) -> Date {
        // JSON and SQLite share the same millisecond timestamp. Discarding
        // submillisecond precision here makes saved results round-trip exactly.
        Date(timeIntervalSince1970: (value.timeIntervalSince1970 * 1_000).rounded() / 1_000)
    }

    private static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension CRMHistorySnapshot {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        checkedAt = try container.decode(Date.self, forKey: .checkedAt)
        status = try container.decode(CRMHistoryCheckStatus.self, forKey: .status)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        let identity = try container.decodeIfPresent(CRMHistoryLookupIdentity.self, forKey: .lookupIdentity)
        lookupIdentity = identity ?? (schemaVersion == 1 ? phone.map(CRMHistoryLookupIdentity.phone) : nil)
        customer = try container.decodeIfPresent(CRMKeyLookupCustomer.self, forKey: .customer)
        matches = try container.decode([CRMPhoneLookupMatch].self, forKey: .matches)
        errorCode = try container.decodeIfPresent(CRMGatewayError.self, forKey: .errorCode)
        metadata = try container.decodeIfPresent(CRMKeyLookupMetadata.self, forKey: .metadata)
    }
}
