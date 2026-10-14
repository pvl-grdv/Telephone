import Foundation
import SQLite3
import Testing
import UseCases

@CallHistoryActor
struct SQLiteCallIdentityTests {
    @Test func persistedIdentityRoundTripsAndRemovesExactCall() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite3")
        let history = SQLiteCallHistory(databaseURL: url, accountUUID: "account-a")
        let sameAddress = URI(user: "+70005550101", host: "", displayName: "Example")
        let first = CallHistoryRecord(uri: sameAddress, date: Date(timeIntervalSinceReferenceDate: 42),
            duration: 12, isIncoming: true, isMissed: false, identifier: "first-uuid")
        let second = CallHistoryRecord(uri: sameAddress, date: first.date, duration: 12,
            isIncoming: true, isMissed: false, identifier: "second-uuid")
        history.add(first)
        history.add(second)
        let reopened = SQLiteCallHistory(databaseURL: url, accountUUID: "account-a")
        #expect(reopened.allRecords.map { $0.identifier } == ["first-uuid", "second-uuid"])
        reopened.remove(reopened.allRecords[0])
        #expect(reopened.allRecords.map { $0.identifier } == ["second-uuid"])
        let other = SQLiteCallHistory(databaseURL: url, accountUUID: "account-b")
        other.add(first)
        #expect(other.allRecords.map { $0.identifier } == ["first-uuid"])
        #expect(reopened.allRecords.map { $0.identifier } == ["second-uuid"])
    }

    @Test func retiredCRMStorageIsPrunedWithoutDeletingCallsOrNotes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite3")
        let history = SQLiteCallHistory(databaseURL: url, accountUUID: "synthetic-account")
        history.add(CallHistoryRecord(
            uri: URI(user: "+70005550101", host: "", displayName: "Example"),
            date: Date(timeIntervalSinceReferenceDate: 42),
            duration: 12, isIncoming: true, isMissed: false,
            identifier: "synthetic-call"
        ))

        let db = try SQLiteConnectionPool.shared.connection(at: url)
        // Finalize all prepared statements before reopening/migrating the
        // SQLite database. An active SELECT cursor blocks DROP TABLE on the
        // pooled connection even when the table being dropped is unrelated.
        do {
            let party = try db.prepare(
                "SELECT party_id FROM calls WHERE account_uuid = 'synthetic-account'"
            )
            #expect(party.step() == SQLITE_ROW)
            let partyID = party.int64(at: 0)
            let note = try db.prepare(
                """
                INSERT INTO party_notes (
                    party_id, account_uuid, call_identifier,
                    body, created_at, updated_at
                ) VALUES (?, 'synthetic-account', 'synthetic-call', 'User note', 1, 1)
                """
            )
            sqlite3_bind_int64(note.handle, 1, partyID)
            try note.stepDone()
        }

        // Simulate a database last opened by the previous version (v4).
        try db.execute(
            "CREATE TABLE call_crm_snapshots (account_uuid TEXT, snapshot_json TEXT)"
        )
        try db.execute(
            "INSERT INTO call_crm_snapshots VALUES ('synthetic-account', '{\"legacy\":true}')"
        )
        try db.execute("CREATE TABLE party_attributes (key TEXT)")
        try db.execute("CREATE TABLE external_refs (provider TEXT)")
        try db.execute("CREATE TABLE crm_sync_state (provider TEXT)")
        try db.execute("PRAGMA user_version = 4")

        let reopened = SQLiteCallHistory(databaseURL: url, accountUUID: "synthetic-account")
        #expect(reopened.allRecords.map(\.identifier) == ["synthetic-call"])
        let version = try db.prepare("PRAGMA user_version")
        #expect(version.step() == SQLITE_ROW)
        #expect(version.int(at: 0) == TelephoneDatabaseSchema.currentVersion)

        for retired in [
            "call_crm_snapshots", "party_attributes",
            "external_refs", "crm_sync_state"
        ] {
            let table = try db.prepare(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?"
            )
            try table.bind(retired, at: 1)
            #expect(table.step() != SQLITE_ROW, "Retired table still exists: \(retired)")
        }
        let notes = try db.prepare("SELECT body FROM party_notes LIMIT 1")
        #expect(notes.step() == SQLITE_ROW)
        #expect(notes.string(at: 0) == "User note")
    }

    @Test func aFreshDatabaseDoesNotCreateRetiredTables() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite3")
        _ = SQLiteCallHistory(databaseURL: url, accountUUID: "synthetic-account")
        let db = try SQLiteConnectionPool.shared.connection(at: url)
        for retired in [
            "call_crm_snapshots", "party_attributes",
            "external_refs", "crm_sync_state"
        ] {
            let table = try db.prepare(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?"
            )
            try table.bind(retired, at: 1)
            #expect(table.step() != SQLITE_ROW, "New database created obsolete table: \(retired)")
        }
    }

    @Test func legacyDerivedIdentityRemainsUnchangedWhenRead() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite3")
        let history = SQLiteCallHistory(databaseURL: url, accountUUID: "legacy")
        let legacy = CallHistoryRecord(uri: URI(user: "101", host: "account.invalid", displayName: ""),
            date: Date(timeIntervalSinceReferenceDate: 15), duration: 0, isIncoming: true, isMissed: true)
        history.add(legacy)
        #expect(history.allRecords.first?.identifier == legacy.identifier)
    }
}
