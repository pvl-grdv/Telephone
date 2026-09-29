import Foundation
import SQLite3
import Testing
import UseCases

@CallHistoryActor
struct CallHistoryCRMStoreTests {
    @Test func migratesVersionTwoWithoutChangingExistingCalls() throws {
        let fixture = try CRMStoreFixture(version: 2)
        defer { fixture.cleanup() }
        try fixture.insertCall(account: "account-a", identifier: "call-a", phone: "70005550101")
        let store = try CallHistoryCRMStore(databaseURL: fixture.url)

        #expect(try store.phone(accountUUID: "account-a", callIdentifier: "call-a") == "70005550101")
        #expect(try fixture.scalar("PRAGMA user_version") == 3)
        #expect(try fixture.scalar("SELECT COUNT(*) FROM calls") == 1)
        #expect(try fixture.scalar("SELECT COUNT(*) FROM call_crm_snapshots") == 0)
        #expect(try store.load(accountUUID: "account-a", callIdentifier: "call-a") == nil)
    }

    @Test func savedCheckCanBeReadAfterCreatingANewStore() throws {
        let fixture = try CRMStoreFixture(version: 2)
        defer { fixture.cleanup() }
        try fixture.insertCall(account: "account-a", identifier: "call-a", phone: "+70005550101")
        let store = try CallHistoryCRMStore(databaseURL: fixture.url)
        let check = makeCheck()
        #expect(try store.save(check, accountUUID: "account-a", callIdentifier: "call-a"))

        let reopened = try CallHistoryCRMStore(databaseURL: fixture.url)
        #expect(try reopened.load(accountUUID: "account-a", callIdentifier: "call-a") == check)
        // Confirm the bytes on disk through an independent connection as well.
        let independent = try SQLiteConnection(url: fixture.url)
        let read = try independent.prepare("SELECT snapshot_json FROM call_crm_snapshots")
        #expect(read.step() == SQLITE_ROW)
        #expect(read.string(at: 0) == check.snapshotJSON)
    }

    @Test func accountsWithTheSameCallIdentifierHaveSeparatePhonesAndChecks() throws {
        let fixture = try CRMStoreFixture(version: 2)
        defer { fixture.cleanup() }
        try fixture.insertCall(account: "account-a", identifier: "same-call", phone: "+70005550101")
        try fixture.insertCall(account: "account-b", identifier: "same-call", phone: "+70005550102")
        let store = try CallHistoryCRMStore(databaseURL: fixture.url)
        let a = makeCheck()
        let b = makeCheck(status: "not-found", companyID: nil, companyName: nil, snapshot: "{\"data\":null}")
        #expect(try store.save(a, accountUUID: "account-a", callIdentifier: "same-call"))
        #expect(try store.save(b, accountUUID: "account-b", callIdentifier: "same-call"))
        #expect(try store.phone(accountUUID: "account-a", callIdentifier: "same-call") == "+70005550101")
        #expect(try store.phone(accountUUID: "account-b", callIdentifier: "same-call") == "+70005550102")
        #expect(try store.load(accountUUID: "account-a", callIdentifier: "same-call") == a)
        #expect(try store.load(accountUUID: "account-b", callIdentifier: "same-call") == b)
        #expect(try store.load(accountUUID: "unknown", callIdentifier: "same-call") == nil)
    }

    @Test func recheckingOverwritesOnlyTheSelectedCallsSnapshot() throws {
        let fixture = try CRMStoreFixture(version: 2)
        defer { fixture.cleanup() }
        try fixture.insertCall(account: "account-a", identifier: "call-a", phone: "+70005550101")
        let store = try CallHistoryCRMStore(databaseURL: fixture.url)
        #expect(try store.save(makeCheck(), accountUUID: "account-a", callIdentifier: "call-a"))
        let updated = makeCheck(status: "ambiguous", companyID: nil, companyName: nil, snapshot: "{\"matches\":[1,2]}")
        #expect(try store.save(updated, accountUUID: "account-a", callIdentifier: "call-a"))
        #expect(try store.load(accountUUID: "account-a", callIdentifier: "call-a") == updated)
        #expect(try fixture.scalar("SELECT COUNT(*) FROM call_crm_snapshots") == 1)
        #expect(try fixture.scalar("SELECT COUNT(*) FROM calls") == 1)
    }

    @Test func deletingACallCascadesAndAnInflightResultCannotResurrectIt() throws {
        let fixture = try CRMStoreFixture(version: 2)
        defer { fixture.cleanup() }
        try fixture.insertCall(account: "account-a", identifier: "call-a", phone: "+70005550101")
        let store = try CallHistoryCRMStore(databaseURL: fixture.url)
        let check = makeCheck()
        #expect(try store.save(check, accountUUID: "account-a", callIdentifier: "call-a"))
        try fixture.connection.execute("DELETE FROM calls WHERE account_uuid = 'account-a'")
        #expect(try fixture.scalar("SELECT COUNT(*) FROM call_crm_snapshots") == 0)
        #expect(try store.phone(accountUUID: "account-a", callIdentifier: "call-a") == nil)
        #expect(try store.load(accountUUID: "account-a", callIdentifier: "call-a") == nil)
        #expect(try !store.save(check, accountUUID: "account-a", callIdentifier: "call-a"))
        #expect(try fixture.scalar("SELECT COUNT(*) FROM calls") == 0)
        #expect(try fixture.scalar("SELECT COUNT(*) FROM call_crm_snapshots") == 0)
    }

    @Test func deletingAllCallsForAnAccountLeavesOtherAccountsChecksIntact() throws {
        let fixture = try CRMStoreFixture(version: 2)
        defer { fixture.cleanup() }
        try fixture.insertCall(account: "account-a", identifier: "same-call", phone: "+70005550101")
        try fixture.insertCall(account: "account-b", identifier: "same-call", phone: "+70005550102")
        let store = try CallHistoryCRMStore(databaseURL: fixture.url)
        #expect(try store.save(makeCheck(), accountUUID: "account-a", callIdentifier: "same-call"))
        #expect(try store.save(makeCheck(), accountUUID: "account-b", callIdentifier: "same-call"))
        try fixture.connection.execute("DELETE FROM calls WHERE account_uuid = 'account-a'")
        #expect(try store.load(accountUUID: "account-a", callIdentifier: "same-call") == nil)
        #expect(try store.load(accountUUID: "account-b", callIdentifier: "same-call") != nil)
    }

    @Test(arguments: [0, 1])
    func unbootstrappedSchemasAreNotAdvancedByCRMStorage(_ version: Int) throws {
        let fixture = try CRMStoreFixture(version: version)
        defer { fixture.cleanup() }
        try fixture.insertCall(account: "account-a", identifier: "call-a", phone: "+70005550101")
        let store = try CallHistoryCRMStore(databaseURL: fixture.url)
        #expect(try store.phone(accountUUID: "account-a", callIdentifier: "call-a") == nil)
        #expect(try store.load(accountUUID: "account-a", callIdentifier: "call-a") == nil)
        #expect(try !store.save(makeCheck(), accountUUID: "account-a", callIdentifier: "call-a"))
        #expect(try fixture.scalar("PRAGMA user_version") == version)
        #expect(try fixture.scalar("SELECT COUNT(*) FROM calls") == 1)
        // The same lazy instance starts working once history finishes bootstrap.
        try fixture.connection.execute("PRAGMA user_version = 2")
        #expect(try store.save(makeCheck(), accountUUID: "account-a", callIdentifier: "call-a"))
        #expect(try fixture.scalar("PRAGMA user_version") == 3)
    }

    @Test func futureSchemaFailsWithoutDowngradingOrWritingACheck() throws {
        let fixture = try CRMStoreFixture(version: 4)
        defer { fixture.cleanup() }
        let store = try CallHistoryCRMStore(databaseURL: fixture.url)
        do {
            _ = try store.save(makeCheck(), accountUUID: "account-a", callIdentifier: "call-a")
            Issue.record("Expected unsupported future schema")
        } catch SQLiteStoreError.unsupportedSchema(let version) {
            #expect(version == 4)
        }
        #expect(try fixture.scalar("PRAGMA user_version") == 4)
        #expect(try fixture.scalar("SELECT COUNT(*) FROM calls") == 0)
    }

    @Test func anAlreadyCancelledSaveDoesNotWriteASnapshot() async throws {
        let fixture = try CRMStoreFixture(version: 2)
        defer { fixture.cleanup() }
        try fixture.insertCall(account: "account-a", identifier: "call-a", phone: "+70005550101")
        let store = try CallHistoryCRMStore(databaseURL: fixture.url)
        _ = try store.phone(accountUUID: "account-a", callIdentifier: "call-a")
        let check = makeCheck()
        let cancelled = Task { @CallHistoryActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try store.save(check, accountUUID: "account-a", callIdentifier: "call-a")
        }
        do {
            _ = try await cancelled.value
            Issue.record("Expected the cancelled save to be rejected")
        } catch is CancellationError {}
        #expect(try store.load(accountUUID: "account-a", callIdentifier: "call-a") == nil)
    }

    private func makeCheck(
        status: String = "loaded", companyID: Int? = 1200456,
        companyName: String? = "Example Company", snapshot: String = "{\"version\":1,\"data\":{\"name\":\"Пример\"}}"
    ) -> StoredCallCRMCheck {
        StoredCallCRMCheck(
            checkedAt: Date(timeIntervalSinceReferenceDate: 123456),
            status: status, companyID: companyID, companyName: companyName,
            snapshotJSON: snapshot
        )
    }
}

@CallHistoryActor
private struct CRMStoreFixture {
    let directory: URL
    let url: URL
    let connection: SQLiteConnection

    init(version: Int) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TelephoneCRMStoreTests-" + UUID().uuidString, isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("Telephone.sqlite3")
        connection = try SQLiteConnectionPool.shared.connection(at: url)
        try connection.execute(
            """
            CREATE TABLE calls (
                account_uuid TEXT NOT NULL,
                identifier TEXT NOT NULL,
                user TEXT NOT NULL,
                PRIMARY KEY (account_uuid, identifier)
            )
            """
        )
        try connection.execute("PRAGMA user_version = \(version)")
    }

    func insertCall(account: String, identifier: String, phone: String) throws {
        let statement = try connection.prepare(
            "INSERT INTO calls(account_uuid,identifier,user) VALUES (?,?,?)"
        )
        try statement.bind(account, at: 1)
        try statement.bind(identifier, at: 2)
        try statement.bind(phone, at: 3)
        try statement.stepDone()
    }

    func scalar(_ sql: String) throws -> Int {
        let statement = try connection.prepare(sql)
        guard statement.step() == SQLITE_ROW else {
            throw SQLiteStoreError.sqlite("Test expected a scalar row")
        }
        return Int(statement.int64(at: 0))
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
