import Foundation
import Testing

struct CRMHistorySnapshotTests {
    @Test func verificationTimestampUsesStableMillisecondPrecision() throws {
        for interval in [1_800_000_000.123456, 1_800_000_000.999876, 978_307_200.000123] {
            let input = Date(timeIntervalSince1970: interval)
            let snapshot = CRMHistorySnapshot.failed(phone: nil, error: .unavailable, checkedAt: input)
            let stored = try snapshot.storedCheck()
            let restored = try CRMHistorySnapshot.restored(from: stored)
            #expect(restored == snapshot)
            #expect(stored.checkedAt == snapshot.checkedAt)
            #expect(abs(snapshot.checkedAt.timeIntervalSince(input)) <= 0.000501)
        }
    }

    @Test func normalizedSnapshotPreservesInventoryAndSafeGatewayEvidence() throws {
        let response = try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: PhoneGatewayFixture.oneMatch())
        let checkedAt = Date(timeIntervalSince1970: 1_800_000_000.125)
        let snapshot = try CRMHistorySnapshot.checked(response: response, phone: "+70005550101", checkedAt: checkedAt)
        let stored = try snapshot.storedCheck()
        let restored = try CRMHistorySnapshot.restored(from: stored)
        #expect(restored == snapshot)
        #expect(stored.checkedAt == checkedAt)
        #expect(stored.status == "matched")
        #expect(stored.companyID == 1200456)
        #expect(snapshot.customer?.company.phone == nil)
        #expect(snapshot.customer?.company.phones == ["+70005550101"])
        #expect(snapshot.customer?.keys[0].programs[0].name == "Sample Program")
        #expect(snapshot.customer?.keys[0].programs.map(\.release) == ["0006", "0010"])
        #expect(snapshot.metadata == response.meta)
        #expect(snapshot.schemaVersion == 2)
        #expect(snapshot.lookupIdentity == .phone("+70005550101"))
        expectNoCredentials(in: stored)
    }

    @Test func snapshotsRequireExplicitChoiceForAmbiguousInventory() throws {
        let response = try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: PhoneGatewayFixture.ambiguous(includeInventory: true))
        #expect(throws: CRMGatewayError.invalidResponse) {
            try CRMHistorySnapshot.checked(response: response, phone: "+70005550101", checkedAt: Date())
        }
        let selected = try CRMHistorySnapshot.checked(
            response: response, phone: "+70005550101", checkedAt: Date(), selectedCompanyID: 1200456
        )
        #expect(selected.status == .matched)
        #expect(selected.customer?.company.id == 1200456)
    }

    @Test func unsafeSavedURLsAndMismatchedColumnsAreRejected() throws {
        let response = try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: PhoneGatewayFixture.oneMatch())
        let stored = try CRMHistorySnapshot.checked(response: response, phone: "+70005550101", checkedAt: Date()).storedCheck()
        let unsafe = StoredCallCRMCheck(
            checkedAt: stored.checkedAt, status: stored.status,
            companyID: stored.companyID, companyName: stored.companyName,
            snapshotJSON: stored.snapshotJSON.replacingOccurrences(of: "integral.ru", with: "other.example")
        )
        #expect(throws: (any Error).self) { try CRMHistorySnapshot.restored(from: unsafe) }
        let wrongColumns = StoredCallCRMCheck(
            checkedAt: stored.checkedAt, status: "failed",
            companyID: stored.companyID, companyName: stored.companyName,
            snapshotJSON: stored.snapshotJSON
        )
        #expect(throws: CRMHistorySnapshotError.invalidSnapshot) {
            try CRMHistorySnapshot.restored(from: wrongColumns)
        }
    }

    @Test func oversizedSnapshotCannotBeSavedAndThenBecomeUnreadable() throws {
        var object = try JSONSerialization.jsonObject(with: PhoneGatewayFixture.oneMatch()) as! [String: Any]
        var customer = object["data"] as! [String: Any]
        var company = customer["company"] as! [String: Any]
        company["name"] = String(repeating: "A", count: CRMHistorySnapshot.maximumJSONBytes)
        customer["company"] = company
        object["data"] = customer
        let data = try JSONSerialization.data(withJSONObject: object)
        let response = try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: data)
        let snapshot = try CRMHistorySnapshot.checked(response: response, phone: "+70005550101", checkedAt: Date())
        #expect(throws: CRMHistorySnapshotError.invalidSnapshot) { try snapshot.storedCheck() }
    }

    @Test func manualKeyPreservesCallerWithoutInventingAPhoneMatch() throws {
        let response = try JSONDecoder().decode(CRMKeyLookupResponse.self, from: PhoneGatewayFixture.keyCustomer())
        for phone in ["+70005550101", nil] as [String?] {
            let snapshot = try CRMHistorySnapshot.checkedKey(
                response: response, keyNumber: 76543, phone: phone, checkedAt: Date()
            )
            let stored = try snapshot.storedCheck()
            #expect(try CRMHistorySnapshot.restored(from: stored) == snapshot)
            #expect(snapshot.status == .matched)
            #expect(snapshot.lookupIdentity == .key(76543))
            #expect(snapshot.phone == phone)
            #expect(snapshot.matches.isEmpty)
            #expect(snapshot.customer?.sourceKeyId == 76543)
            #expect(snapshot.customer?.company.phone == nil)
            #expect(snapshot.customer?.company.phones == ["+12025550100"])
            #expect(snapshot.customer?.keys[0].url.absoluteString == "https://integral.ru/personal/keys/01-20-0456/76543/")
            #expect(snapshot.customer?.keys[0].programs.map(\.release) == ["0006", "0010"])
            expectNoCredentials(in: stored)
        }
    }

    @Test func manualKeyRejectsWrongSourceAndMissingInventory() throws {
        let data = try PhoneGatewayFixture.keyCustomer()
        let response = try JSONDecoder().decode(CRMKeyLookupResponse.self, from: data)
        #expect(throws: CRMGatewayError.invalidResponse) {
            try CRMHistorySnapshot.checkedKey(response: response, keyNumber: 76544, phone: nil, checkedAt: Date())
        }
        var root = try object(data)
        var customer = root["data"] as! [String: Any]
        customer["keys"] = [] as [Any]
        root["data"] = customer
        let withoutInventory = try JSONDecoder().decode(CRMKeyLookupResponse.self, from: json(root))
        #expect(throws: CRMGatewayError.invalidResponse) {
            try CRMHistorySnapshot.checkedKey(response: withoutInventory, keyNumber: 76543, phone: nil, checkedAt: Date())
        }
    }

    @Test func manualEmailStoresCanonicalContactAndSeparateCaller() throws {
        var root = try emailObject()
        // Extra upstream fields cannot become credential material in the dated result.
        root["crmCredentials"] = ["email": "login@example.invalid", "password": "fictional-password"]
        root["Authorization"] = "Bearer fictional-token"
        let response = try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: json(root))
        for phone in ["+70005550101", nil] as [String?] {
            let snapshot = try CRMHistorySnapshot.checkedEmail(
                response: response, email: "  Agent@Example.Invalid  ", phone: phone, checkedAt: Date()
            )
            let stored = try snapshot.storedCheck()
            #expect(try CRMHistorySnapshot.restored(from: stored) == snapshot)
            #expect(snapshot.status == .matched)
            #expect(snapshot.lookupIdentity == .email("agent@example.invalid"))
            #expect(snapshot.phone == phone)
            #expect(snapshot.customer?.sourceKeyId == nil)
            #expect(snapshot.customer?.company.phone == nil)
            #expect(snapshot.customer?.company.phones == ["+12025550100"])
            #expect(snapshot.customer?.company.emails == ["agent@example.invalid"])
            #expect(snapshot.customer?.keys[0].programs[0].keyUrl == snapshot.customer?.keys[0].url)
            expectNoCredentials(in: stored)
        }
    }

    @Test func manualEmailRequiresExactCanonicalInventoryContact() throws {
        for emails in [
            nil, ["other@example.invalid"], ["Agent@example.invalid"],
            ["agent@example.invalid", "agent@example.invalid"],
        ] as [[String]?] {
            var root = try emailObject()
            var customer = root["data"] as! [String: Any]
            var company = customer["company"] as! [String: Any]
            company["emails"] = emails
            customer["company"] = company
            root["data"] = customer
            let response = try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: json(root))
            #expect(throws: CRMGatewayError.invalidResponse) {
                try CRMHistorySnapshot.checkedEmail(
                    response: response, email: "agent@example.invalid", phone: nil, checkedAt: Date()
                )
            }
        }
        let response = try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: json(emailObject()))
        #expect(throws: CRMGatewayError.invalidResponse) {
            try CRMHistorySnapshot.checkedEmail(
                response: response, email: "agent*@example.invalid", phone: nil, checkedAt: Date()
            )
        }
    }

    @Test func manualEmailAmbiguityNeedsAnExplicitOrganizationChoice() throws {
        let root = try emailObject(ambiguous: true)
        let response = try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: json(root))
        #expect(throws: CRMGatewayError.invalidResponse) {
            try CRMHistorySnapshot.checkedEmail(
                response: response, email: "agent@example.invalid", phone: nil, checkedAt: Date()
            )
        }
        let selected = try CRMHistorySnapshot.checkedEmail(
            response: response, email: "agent@example.invalid", phone: nil,
            checkedAt: Date(), selectedCompanyID: 1200456
        )
        #expect(selected.status == .matched)
        #expect(selected.matches.count == 2)
        #expect(try CRMHistorySnapshot.restored(from: selected.storedCheck()) == selected)

        var unresolvedRoot = root
        unresolvedRoot["data"] = NSNull()
        let unresolvedResponse = try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: json(unresolvedRoot))
        let unresolved = try CRMHistorySnapshot.checkedEmail(
            response: unresolvedResponse, email: "agent@example.invalid", phone: nil, checkedAt: Date()
        )
        #expect(unresolved.status == .ambiguous)
        #expect(try CRMHistorySnapshot.restored(from: unresolved.storedCheck()) == unresolved)
    }

    @Test func internalCallerCanPersistManualNotFoundAndFailureProvenance() throws {
        var root = try object(PhoneGatewayFixture.oneMatch())
        root["data"] = NSNull()
        root["matches"] = [] as [Any]
        let keyResponse = try JSONDecoder().decode(CRMKeyLookupResponse.self, from: json(root))
        let emailResponse = try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: json(root))
        let snapshots = [
            try CRMHistorySnapshot.checkedKey(response: keyResponse, keyNumber: 76543, phone: nil, checkedAt: Date()),
            try CRMHistorySnapshot.checkedEmail(response: emailResponse, email: "agent@example.invalid", phone: nil, checkedAt: Date()),
            CRMHistorySnapshot.failed(phone: nil, error: .unavailable, checkedAt: Date(), lookupIdentity: .key(76543)),
            CRMHistorySnapshot.failed(phone: nil, error: .unauthorized, checkedAt: Date(), lookupIdentity: .email("agent@example.invalid")),
        ]
        for snapshot in snapshots {
            #expect(snapshot.phone == nil)
            #expect(snapshot.lookupIdentity != nil)
            #expect(try CRMHistorySnapshot.restored(from: snapshot.storedCheck()) == snapshot)
        }
        #expect(snapshots[0].status == .notFound)
        #expect(snapshots[1].status == .notFound)
        #expect(snapshots[2].status == .failed)
    }

    @Test func versionOnePhoneSnapshotRestoresItsOriginalLookupIdentity() throws {
        let response = try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: PhoneGatewayFixture.oneMatch())
        let stored = try CRMHistorySnapshot.checked(response: response, phone: "+70005550101", checkedAt: Date()).storedCheck()
        var root = try object(Data(stored.snapshotJSON.utf8))
        root["schemaVersion"] = 1
        root.removeValue(forKey: "lookup")
        let legacy = try replacingJSON(in: stored, with: root)
        let restored = try CRMHistorySnapshot.restored(from: legacy)
        #expect(restored.schemaVersion == 1)
        #expect(restored.lookupIdentity == .phone("+70005550101"))
        #expect(restored.customer?.keys[0].programs.map(\.release) == ["0006", "0010"])
        #expect(try CRMHistorySnapshot.restored(from: restored.storedCheck()) == restored)
    }

    @Test func malformedProvenanceAndUnsafeManualSnapshotsAreRejected() throws {
        let response = try JSONDecoder().decode(CRMKeyLookupResponse.self, from: PhoneGatewayFixture.keyCustomer())
        let stored = try CRMHistorySnapshot.checkedKey(response: response, keyNumber: 76543, phone: nil, checkedAt: Date()).storedCheck()
        let original = try object(Data(stored.snapshotJSON.utf8))
        for identity in [
            ["kind": "key", "value": "076543"],
            ["kind": "key", "value": "76544"],
            ["kind": "email", "value": "agent@example.invalid"],
            ["kind": "phone", "value": "+70005550101"],
        ] {
            var root = original
            root["lookup"] = identity
            #expect(throws: (any Error).self) { try CRMHistorySnapshot.restored(from: replacingJSON(in: stored, with: root)) }
        }
        for schemaVersion in [2, 3] {
            var root = original
            root["schemaVersion"] = schemaVersion
            root.removeValue(forKey: "lookup")
            #expect(throws: (any Error).self) { try CRMHistorySnapshot.restored(from: replacingJSON(in: stored, with: root)) }
        }
        let unsafe = StoredCallCRMCheck(
            checkedAt: stored.checkedAt, status: stored.status,
            companyID: stored.companyID, companyName: stored.companyName,
            snapshotJSON: stored.snapshotJSON.replacingOccurrences(of: "integral.ru", with: "other.example")
        )
        #expect(throws: (any Error).self) { try CRMHistorySnapshot.restored(from: unsafe) }
    }

    @Test func manualLookupRejectsIncompleteOrMalformedMetadata() throws {
        for (field, value) in [("complete", false as Any), ("requestId", "" as Any), ("fetchedAt", "not-a-date" as Any)] {
            var root = try object(PhoneGatewayFixture.keyCustomer())
            var metadata = root["meta"] as! [String: Any]
            metadata[field] = value
            root["meta"] = metadata
            let response = try JSONDecoder().decode(CRMKeyLookupResponse.self, from: json(root))
            #expect(throws: (any Error).self) {
                try CRMHistorySnapshot.checkedKey(response: response, keyNumber: 76543, phone: nil, checkedAt: Date())
            }
        }
    }

    private func emailObject(ambiguous: Bool = false) throws -> [String: Any] {
        var root = try object(ambiguous ? PhoneGatewayFixture.ambiguous(includeInventory: true) : PhoneGatewayFixture.oneMatch())
        var customer = root["data"] as! [String: Any]
        var company = customer["company"] as! [String: Any]
        company["phone"] = "+12025550100, legacy text"
        company["phones"] = ["+12025550100"]
        company["emails"] = ["agent@example.invalid"]
        customer["company"] = company
        root["data"] = customer
        return root
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func replacingJSON(in check: StoredCallCRMCheck, with object: [String: Any]) throws -> StoredCallCRMCheck {
        StoredCallCRMCheck(
            checkedAt: check.checkedAt, status: check.status,
            companyID: check.companyID, companyName: check.companyName,
            snapshotJSON: String(decoding: try json(object), as: UTF8.self)
        )
    }

    private func expectNoCredentials(in check: StoredCallCRMCheck) {
        for forbiddenKey in ["Authorization", "token", "origin", "password", "crmCredentials", "rawResponse", "rawHeaders"] {
            #expect(!check.snapshotJSON.contains("\"\(forbiddenKey)\""))
        }
        #expect(!check.snapshotJSON.contains("Bearer fictional-token"))
        #expect(!check.snapshotJSON.contains("fictional-password"))
    }
}
