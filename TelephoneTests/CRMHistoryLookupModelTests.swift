import Foundation
import Testing

@MainActor
struct CRMHistoryLookupModelTests {
    @Test func freshHistoryCheckUsesStoredPeerPhoneAndPersistsCurrentEvidence() async throws {
        let fixture = try await makeFixture()
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a", checkNow: true)
        await waitUntilIdle(fixture.model)
        #expect(await fixture.provider.calls.map(\.phone) == ["+70005550101"])
        #expect(await fixture.provider.keyCalls == 0)
        #expect(await fixture.provider.appendCalls == 0)
        #expect(fixture.model.snapshot?.checkedAt == fixture.now)
        #expect(fixture.model.snapshot?.status == .matched)
        let saved = await fixture.storage.saved
        #expect(saved.count == 1)
        #expect(saved.first?.accountUUID == "account-a")
        #expect(saved.first?.callIdentifier == "call-a")
        #expect(saved.first?.check.checkedAt == fixture.now)
        #expect(fixture.model.localError == nil)
    }

    @Test func reopeningSavedCheckDoesNotContactCRMAndKeepsItsOriginalCheckedAt() async throws {
        let fixture = try await makeFixture()
        let oldDate = fixture.now.addingTimeInterval(-3600)
        let response = try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: PhoneGatewayFixture.oneMatch())
        let old = try CRMHistorySnapshot.checked(response: response, phone: "+70005550101", checkedAt: oldDate).storedCheck()
        await fixture.storage.setStored(old)
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a")
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.snapshot?.checkedAt == oldDate)
        #expect(await fixture.provider.calls.isEmpty)
        #expect(await fixture.storage.saved.isEmpty)
    }

    @Test func cachedResultStaysVisibleWhileFreshLookupIsPending() async throws {
        let fixture = try await makeFixture(hold: true)
        let oldDate = fixture.now.addingTimeInterval(-3600)
        let response = try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: PhoneGatewayFixture.oneMatch())
        let old = try CRMHistorySnapshot.checked(response: response, phone: "+70005550101", checkedAt: oldDate).storedCheck()
        await fixture.storage.setStored(old)
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a", checkNow: true)
        await fixture.provider.waitForRequest()
        #expect(fixture.model.isChecking)
        #expect(fixture.model.snapshot?.checkedAt == oldDate)
        await fixture.provider.finishPending()
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.snapshot?.checkedAt == fixture.now)
    }

    @Test func ambiguityIsSavedAndSelectionRevalidatesTheSamePhone() async throws {
        let fixture = try await makeFixture(response: PhoneGatewayFixture.ambiguous())
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a", checkNow: true)
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.snapshot?.status == .ambiguous)
        #expect(await fixture.storage.saved.count == 1)
        let match = try #require(fixture.model.snapshot?.matches.first)
        fixture.model.chooseCompany(match)
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.snapshot?.status == .matched)
        #expect(await fixture.provider.calls.map(\.companyID) == [nil, 1200456])
        #expect(await fixture.storage.saved.count == 2)
        #expect(await fixture.provider.appendCalls == 0)
    }

    @Test func notFoundAndGatewayFailureProduceDifferentPersistedStatuses() async throws {
        let none = Data(#"""
        {"data":null,"matches":[],"meta":{"requestId":"fictional-history-none","fetchedAt":"2026-01-01T12:00:00Z","complete":true,"fromCache":false}}
        """#.utf8)
        let missing = try await makeFixture(response: none)
        missing.model.load(accountUUID: "account-a", callIdentifier: "call-a", checkNow: true)
        await waitUntilIdle(missing.model)
        #expect(missing.model.snapshot?.status == .notFound)
        #expect(await missing.storage.saved.first?.check.status == "notFound")
        let failed = try await makeFixture()
        await failed.provider.setError(.unavailable)
        failed.model.load(accountUUID: "account-a", callIdentifier: "call-a", checkNow: true)
        await waitUntilIdle(failed.model)
        #expect(failed.model.snapshot?.status == .failed)
        #expect(failed.model.snapshot?.errorCode == .unavailable)
        #expect(await failed.storage.saved.first?.check.status == "failed")
        #expect(await failed.provider.calls.count == 1)
    }

    @Test func internalExtensionNeverContactsCRMAndPersistsTypedFailure() async throws {
        let fixture = try await makeFixture()
        await fixture.storage.setFirstPhone("1234")
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a", checkNow: true)
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.callerPhone == nil)
        #expect(fixture.model.snapshot?.status == .failed)
        #expect(fixture.model.snapshot?.errorCode == .invalidPhoneNumber)
        #expect(await fixture.provider.calls.isEmpty)
        #expect(await fixture.provider.keyCalls == 0)
        #expect(await fixture.provider.appendCalls == 0)
        #expect(await fixture.storage.saved.first?.check.status == "failed")
    }

    @Test func cancelCheckKeepsSavedResultAndRejectsALateNetworkReply() async throws {
        let fixture = try await makeFixture(hold: true)
        let response = try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: PhoneGatewayFixture.oneMatch())
        let oldDate = fixture.now.addingTimeInterval(-3600)
        let old = try CRMHistorySnapshot.checked(response: response, phone: "+70005550101", checkedAt: oldDate).storedCheck()
        await fixture.storage.setStored(old)
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a", checkNow: true)
        await fixture.provider.waitForRequest()
        fixture.model.cancelCheck()
        await fixture.provider.finishPending()
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.snapshot?.checkedAt == oldDate)
        #expect(await fixture.storage.saved.isEmpty)
        #expect(fixture.model.canCheck)
    }

    @Test(arguments: ["switch", "close", "settings"])
    func lateNetworkRepliesCannotSaveAfterContextOrSettingsChanges(_ change: String) async throws {
        let fixture = try await makeFixture(hold: true)
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a", checkNow: true)
        await fixture.provider.waitForRequest()
        switch change {
        case "switch":
            fixture.model.load(accountUUID: "account-b", callIdentifier: "call-b")
        case "settings":
            try await fixture.settings.save(enabled: true, origin: "https://other.example", newToken: "fictional-other-token")
        default:
            fixture.model.close()
        }
        await fixture.provider.finishPending()
        await waitUntilIdle(fixture.model)
        #expect(await fixture.storage.saved.isEmpty)
        #expect(fixture.model.snapshot == nil)
        if change == "switch" { #expect(fixture.model.callerPhone == "+12025550100") }
    }

    @Test func deletingExistingCallPreventsSnapshotResurrection() async throws {
        let fixture = try await makeFixture(hold: true)
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a", checkNow: true)
        await fixture.provider.waitForRequest()
        await fixture.storage.deleteFirstCall()
        await fixture.provider.finishPending()
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.localError == .recordRemoved)
        #expect(await fixture.storage.saved.isEmpty)
        #expect(!fixture.model.canCheck)
    }

    @Test func localSaveFailureIsVisibleAndDoesNotBecomeAGatewayFailure() async throws {
        let fixture = try await makeFixture()
        await fixture.storage.failWrites()
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a", checkNow: true)
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.snapshot?.status == .matched)
        #expect(fixture.model.localError == .saveFailed)
        #expect(await fixture.storage.saved.isEmpty)
    }

    @Test func manualKeyWorksWithoutEligiblePhoneAndRefreshKeepsKeyProvenance() async throws {
        let fixture = try await makeFixture()
        await fixture.storage.setFirstPhone("1234")
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a")
        await waitUntilIdle(fixture.model)
        fixture.model.keyNumber = "76543"
        fixture.model.searchKey()
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.snapshot?.status == .matched)
        #expect(fixture.model.snapshot?.phone == nil)
        #expect(fixture.model.snapshot?.lookupIdentity == .key(76543))
        #expect(await fixture.provider.calls.isEmpty)
        #expect(await fixture.provider.keyCalls == 1)
        fixture.model.close()
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a", checkNow: true)
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.keyNumber == "76543")
        #expect(fixture.model.snapshot?.lookupIdentity == .key(76543))
        #expect(await fixture.provider.keyCalls == 2)
        #expect(await fixture.provider.calls.isEmpty)
        #expect(await fixture.provider.appendCalls == 0)
        #expect(await fixture.storage.saved.count == 2)
    }

    @Test func manualEmailChoicesRevalidateAndReopeningSavedResultDoesNotSearch() async throws {
        let fixture = try await makeFixture()
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a")
        await waitUntilIdle(fixture.model)
        fixture.model.email = " Person@Example.test "
        fixture.model.searchEmail()
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.snapshot?.status == .ambiguous)
        #expect(fixture.model.snapshot?.lookupIdentity == .email("person@example.test"))
        let match = try #require(fixture.model.snapshot?.matches.first)
        fixture.model.chooseCompany(match)
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.snapshot?.status == .matched)
        #expect(fixture.model.snapshot?.customer?.company.phones == [])
        #expect(fixture.model.snapshot?.phone == "+70005550101")
        #expect(await fixture.provider.emailCalls.map(\.companyID) == [nil, 1200456])
        #expect(await fixture.provider.calls.isEmpty)
        #expect(await fixture.provider.appendCalls == 0)
        fixture.model.close()
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a")
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.email == "person@example.test")
        #expect(fixture.model.snapshot?.status == .matched)
        #expect(await fixture.provider.emailCalls.count == 2)
        fixture.model.close()
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a", checkNow: true)
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.snapshot?.status == .matched)
        #expect(fixture.model.snapshot?.lookupIdentity == .email("person@example.test"))
        #expect(await fixture.provider.emailCalls.map(\.companyID) == [nil, 1200456, 1200456])
        #expect(await fixture.provider.calls.isEmpty)
        #expect(await fixture.provider.appendCalls == 0)
    }

    @Test func editingManualEmailCancelsPendingResultWithoutOverwritingSavedCheck() async throws {
        let fixture = try await makeFixture(hold: true)
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a")
        await waitUntilIdle(fixture.model)
        fixture.model.email = "person@example.test"
        fixture.model.searchEmail()
        await fixture.provider.waitForRequest()
        fixture.model.email = "other@example.test"
        await fixture.provider.finishPending()
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.snapshot == nil)
        #expect(await fixture.storage.saved.isEmpty)
    }

    @Test func savedKeyRequiresFreshLookupAndExplicitConfirmationBeforeOneAppend() async throws {
        let fixture = try await linkFixture()
        #expect(await fixture.provider.keyCalls == 0)
        #expect(fixture.model.canLinkPhone)
        fixture.model.preparePhoneLink()
        await waitForLinkPreparation(fixture.model)
        let first = try #require(fixture.model.pendingPhoneLink)
        #expect(first.phone == "+70005550101")
        #expect(first.companyID == 1200456)
        #expect(first.sourceKeyID == 76543)
        #expect(first.expectedPhone == "+12025550100, legacy text")
        #expect(await fixture.provider.keyCalls == 1)
        #expect(await fixture.provider.appendCalls == 0)
        fixture.model.dismissPhoneLinkConfirmation()
        fixture.model.confirmPhoneLink(first)
        #expect(await fixture.provider.appendCalls == 0)
        fixture.model.preparePhoneLink()
        await waitForLinkPreparation(fixture.model)
        let second = try #require(fixture.model.pendingPhoneLink)
        await fixture.provider.setAppendData(try PhoneGatewayFixture.appended())
        fixture.model.confirmPhoneLink(second)
        fixture.model.dismissPhoneLinkConfirmation()
        fixture.model.confirmPhoneLink(second)
        await waitForLinkSettled(fixture.model)
        fixture.model.confirmPhoneLink(second)
        #expect(fixture.model.phoneLinkState == .saved(added: true))
        #expect(await fixture.provider.appendCalls == 1)
        let append = try #require(await fixture.provider.appendArguments.first)
        #expect(append.phone == "+70005550101")
        #expect(append.companyID == 1200456)
        #expect(append.sourceKeyID == 76543)
        #expect(append.expectedPhone == "+12025550100, legacy text")
        #expect(fixture.model.snapshot?.customer?.company.phone == nil)
        #expect(fixture.model.snapshot?.customer?.company.phones?.contains("+70005550101") == true)
        #expect(fixture.model.isCallerLinkedToKey)
        #expect(!fixture.model.canLinkPhone)
        let saved = try #require(await fixture.storage.saved.first)
        #expect(saved.accountUUID == "account-a" && saved.callIdentifier == "call-a")
        #expect(!saved.check.snapshotJSON.contains("legacy text"))
        #expect(saved.check.checkedAt == fixture.now)
        fixture.model.close()
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a")
        await waitUntilIdle(fixture.model)
        #expect(fixture.model.isCallerLinkedToKey)
        #expect(await fixture.provider.keyCalls == 2)
        #expect(await fixture.provider.appendCalls == 1)
    }

    @Test func emailOrInvalidCallerCannotOfferHistoryAppend() async throws {
        let email = try await makeFixture()
        email.model.load(accountUUID: "account-a", callIdentifier: "call-a")
        await waitUntilIdle(email.model)
        email.model.email = "person@example.test"
        email.model.searchEmail()
        await waitUntilIdle(email.model)
        let match = try #require(email.model.snapshot?.matches.first)
        email.model.chooseCompany(match)
        await waitUntilIdle(email.model)
        #expect(!email.model.canLinkPhone)
        email.model.preparePhoneLink()
        #expect(email.model.pendingPhoneLink == nil)
        #expect(await email.provider.appendCalls == 0)

        let extensionCall = try await linkFixture()
        await extensionCall.storage.setFirstPhone("1234")
        extensionCall.model.close()
        extensionCall.model.load(accountUUID: "account-a", callIdentifier: "call-a")
        await waitUntilIdle(extensionCall.model)
        #expect(!extensionCall.model.canLinkPhone)
        extensionCall.model.preparePhoneLink()
        #expect(await extensionCall.provider.appendCalls == 0)
    }

    @Test func deletionAndSettingsChangeBeforeConfirmationBlockTheWrite() async throws {
        for change in ["delete", "settings", "close"] {
            let fixture = try await linkFixture()
            fixture.model.preparePhoneLink()
            await waitForLinkPreparation(fixture.model)
            let confirmation = try #require(fixture.model.pendingPhoneLink)
            switch change {
            case "delete": await fixture.storage.deleteFirstCall()
            case "settings": try await fixture.settings.save(enabled: true, origin: "https://other.example", newToken: "fictional-other-token")
            default: fixture.model.close()
            }
            fixture.model.confirmPhoneLink(confirmation)
            await waitForLinkSettled(fixture.model)
            #expect(await fixture.provider.appendCalls == 0)
            if change == "delete" { #expect(fixture.model.localError == .recordRemoved) }
        }
    }

    @Test func staleFreshKeyOwnerOrCancelledPreparationCannotOfferConfirmation() async throws {
        let ownerChanged = try await linkFixture()
        let moved = String(decoding: try PhoneGatewayFixture.keyCustomer(), as: UTF8.self)
            .replacingOccurrences(of: "1200456", with: "2200456")
            .replacingOccurrences(of: "01-20-0456", with: "02-20-0456")
        await ownerChanged.provider.setKeyResponse(Data(moved.utf8))
        ownerChanged.model.preparePhoneLink()
        await waitForLinkPreparation(ownerChanged.model)
        #expect(ownerChanged.model.pendingPhoneLink == nil)
        #expect(ownerChanged.model.phoneLinkState == .failed(.conflict))
        #expect(await ownerChanged.provider.appendCalls == 0)

        let cancelled = try await linkFixture()
        await cancelled.provider.holdNextKeyLookup()
        cancelled.model.preparePhoneLink()
        await cancelled.provider.waitForRequest()
        cancelled.model.close()
        await cancelled.provider.finishPending()
        await waitForLinkSettled(cancelled.model)
        #expect(cancelled.model.pendingPhoneLink == nil)
        #expect(await cancelled.provider.appendCalls == 0)
    }

    @Test(arguments: [CRMGatewayError.forbidden, .unauthorized, .conflict, .rateLimited, .unavailable])
    func failedAppendKeepsTypedRefusalsAndRequiresFreshKeyBeforeRetry(_ failure: CRMGatewayError) async throws {
        let fixture = try await linkFixture()
        fixture.model.preparePhoneLink()
        await waitForLinkPreparation(fixture.model)
        let confirmation = try #require(fixture.model.pendingPhoneLink)
        await fixture.provider.setAppendError(failure)
        fixture.model.confirmPhoneLink(confirmation)
        await waitForLinkSettled(fixture.model)
        let expected: CRMGatewayError = failure == .unavailable ? .phoneWriteUnconfirmed : failure
        #expect(fixture.model.phoneLinkState == .failed(expected))
        fixture.model.confirmPhoneLink(confirmation)
        #expect(await fixture.provider.appendCalls == 1)
        fixture.model.preparePhoneLink()
        await waitForLinkPreparation(fixture.model)
        #expect(await fixture.provider.keyCalls == 2)
        #expect(await fixture.provider.appendCalls == 1)
    }

    @Test func localSaveFailureAfterAppendDoesNotMasqueradeAsWriteFailure() async throws {
        let fixture = try await linkFixture()
        fixture.model.preparePhoneLink()
        await waitForLinkPreparation(fixture.model)
        let confirmation = try #require(fixture.model.pendingPhoneLink)
        await fixture.storage.failWrites()
        await fixture.provider.setAppendData(try PhoneGatewayFixture.appended())
        fixture.model.confirmPhoneLink(confirmation)
        await waitForLinkSettled(fixture.model)
        #expect(fixture.model.phoneLinkState == .saved(added: true))
        #expect(fixture.model.localError == .saveFailed)
        #expect(await fixture.provider.appendCalls == 1)
        #expect(await fixture.storage.saved.isEmpty)
    }

    private func linkFixture() async throws -> HistoryFixture {
        let fixture = try await makeFixture()
        let data = try PhoneGatewayFixture.keyCustomer()
        await fixture.provider.setKeyResponse(data)
        let response = try JSONDecoder().decode(CRMKeyLookupResponse.self, from: data)
        let old = try CRMHistorySnapshot.checkedKey(
            response: response, keyNumber: 76543, phone: "+70005550101",
            checkedAt: fixture.now.addingTimeInterval(-3600)
        ).storedCheck()
        await fixture.storage.setStored(old)
        fixture.model.load(accountUUID: "account-a", callIdentifier: "call-a")
        await waitUntilIdle(fixture.model)
        return fixture
    }

    private func waitForLinkPreparation(_ model: CRMHistoryLookupModel) async {
        for _ in 0..<200 where model.phoneLinkState == .refreshing {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.phoneLinkState != .refreshing)
    }

    private func waitForLinkSettled(_ model: CRMHistoryLookupModel) async {
        for _ in 0..<200 where model.phoneLinkState == .saving || model.phoneLinkState == .refreshing || model.isSaving {
            try? await Task.sleep(for: .milliseconds(5))
        }
        for _ in 0..<10 { await Task.yield() }
        #expect(model.phoneLinkState != .saving && model.phoneLinkState != .refreshing && !model.isSaving)
    }

    private func makeFixture(response: Data? = nil, hold: Bool = false) async throws -> HistoryFixture {
        let defaults = UserDefaults(suiteName: "CRMHistoryModelTests.\(UUID().uuidString)")!
        let settings = CRMGatewaySettings(defaults: defaults, tokenStore: HistoryTokenFake())
        try await settings.save(enabled: true, origin: "https://gateway.example", newToken: "fictional-history-token")
        let storage = HistoryStorageFake()
        let provider = HistoryProviderFake(response: try response ?? PhoneGatewayFixture.oneMatch(), hold: hold)
        let now = Date(timeIntervalSince1970: 1_800_000_000.125)
        let model = CRMHistoryLookupModel(storage: storage, settings: settings, provider: provider, now: { now })
        return HistoryFixture(settings: settings, storage: storage, provider: provider, model: model, now: now)
    }

    private func waitUntilIdle(_ model: CRMHistoryLookupModel) async {
        for _ in 0..<200 where model.isLoading || model.isChecking || model.isSaving {
            try? await Task.sleep(for: .milliseconds(5))
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(!model.isLoading && !model.isChecking && !model.isSaving)
    }
}

@MainActor
private struct HistoryFixture {
    let settings: CRMGatewaySettings
    let storage: HistoryStorageFake
    let provider: HistoryProviderFake
    let model: CRMHistoryLookupModel
    let now: Date
}

private actor HistoryTokenFake: CRMGatewayTokenStoring {
    var values: [String: String] = [:]
    func token(for origin: String) -> String { values[origin] ?? "" }
    func save(_ token: String, for origin: String) -> Bool { values[origin] = token; return true }
    func remove(for origin: String) -> Bool { values.removeValue(forKey: origin); return true }
}

private actor HistoryStorageFake: CallHistoryCRMStorage {
    struct Saved: Sendable {
        let accountUUID: String
        let callIdentifier: String
        let check: StoredCallCRMCheck
    }
    private var rows: [String: String] = ["account-a/call-a": "8 (000) 555-01-01", "account-b/call-b": "+12025550100"]
    private var checks: [String: StoredCallCRMCheck] = [:]
    private var writeFails = false
    private(set) var saved: [Saved] = []

    func phone(accountUUID: String, callIdentifier: String) -> String? { rows[accountUUID + "/" + callIdentifier] }
    func load(accountUUID: String, callIdentifier: String) -> StoredCallCRMCheck? { checks[accountUUID + "/" + callIdentifier] }
    func save(_ check: StoredCallCRMCheck, accountUUID: String, callIdentifier: String) throws -> Bool {
        try Task.checkCancellation()
        if writeFails { throw CocoaError(.fileWriteUnknown) }
        let key = accountUUID + "/" + callIdentifier
        guard rows[key] != nil else { return false }
        checks[key] = check
        saved.append(Saved(accountUUID: accountUUID, callIdentifier: callIdentifier, check: check))
        return true
    }
    func setStored(_ check: StoredCallCRMCheck) { checks["account-a/call-a"] = check }
    func setFirstPhone(_ phone: String) { rows["account-a/call-a"] = phone }
    func deleteFirstCall() { rows.removeValue(forKey: "account-a/call-a"); checks.removeValue(forKey: "account-a/call-a") }
    func failWrites() { writeFails = true }
}

private actor HistoryProviderFake: CRMKeyLookupProvider {
    struct Call: Sendable { let phone: String; let companyID: Int? }
    struct EmailCall: Sendable { let email: String; let companyID: Int? }
    struct AppendCall: Sendable { let phone: String; let companyID: Int; let sourceKeyID: Int; let expectedPhone: String }
    let response: Data
    let hold: Bool
    private var error: CRMGatewayError?
    private var pending: CheckedContinuation<Void, Never>?
    private var ready: CheckedContinuation<Void, Never>?
    private var keyResponse = GatewayFixture.customer
    private var holdKey = false
    private var appendError: CRMGatewayError? = .forbidden
    private var appendData: Data?
    private(set) var calls: [Call] = []
    private(set) var emailCalls: [EmailCall] = []
    private(set) var keyCalls = 0
    private(set) var appendCalls = 0
    private(set) var appendArguments: [AppendCall] = []
    init(response: Data, hold: Bool) { self.response = response; self.hold = hold }
    func customer(forKeyNumber keyNumber: Int, configuration: CRMGatewayConfiguration) async throws -> CRMKeyLookupResponse {
        keyCalls += 1
        if holdKey {
            holdKey = false
            await withCheckedContinuation { continuation in
                pending = continuation
                ready?.resume()
                ready = nil
            }
        }
        return try JSONDecoder().decode(CRMKeyLookupResponse.self, from: keyResponse)
    }
    func customer(forEmail email: String, companyID: Int?, configuration: CRMGatewayConfiguration) async throws -> CRMPhoneLookupResponse {
        emailCalls.append(EmailCall(email: email, companyID: companyID))
        if hold {
            await withCheckedContinuation { continuation in
                pending = continuation
                ready?.resume()
                ready = nil
            }
        }
        if let error { throw error }
        return try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: EmailGatewayFixture.ambiguous(includeInventory: companyID != nil))
    }
    func customer(forPhoneNumber phoneNumber: String, companyID: Int?, configuration: CRMGatewayConfiguration) async throws -> CRMPhoneLookupResponse {
        calls.append(Call(phone: phoneNumber, companyID: companyID))
        if hold {
            await withCheckedContinuation { continuation in
                pending = continuation
                ready?.resume()
                ready = nil
            }
        }
        if let error { throw error }
        let data = try companyID == nil ? response : PhoneGatewayFixture.ambiguous(includeInventory: true)
        return try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: data)
    }
    func appendPhone(_ phoneNumber: String, companyID: Int, sourceKeyID: Int, expectedPhone: String, configuration: CRMGatewayConfiguration) throws -> CRMPhoneAppendResponse {
        appendCalls += 1
        appendArguments.append(AppendCall(phone: phoneNumber, companyID: companyID, sourceKeyID: sourceKeyID, expectedPhone: expectedPhone))
        if let appendError { throw appendError }
        guard let appendData else { throw CRMGatewayError.invalidResponse }
        return try JSONDecoder().decode(CRMPhoneAppendResponse.self, from: appendData)
    }
    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { ready = $0 }
    }
    func finishPending() { pending?.resume(); pending = nil }
    func setError(_ value: CRMGatewayError) { error = value }
    func setKeyResponse(_ data: Data) { keyResponse = data }
    func holdNextKeyLookup() { holdKey = true }
    func setAppendError(_ value: CRMGatewayError) { appendError = value }
    func setAppendData(_ data: Data) { appendError = nil; appendData = data }
}
