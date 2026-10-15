import Foundation
import SQLite3
import Testing
import UseCases

@CallHistoryActor
struct SQLiteCallIdentityTests {
    @Test func persistedIdentityRoundTripsAndRemovesExactCall() throws {
        let url = temporaryDatabase()
        let history = SQLiteCallHistory(databaseURL: url, accountUUID: "account-a")
        let sameAddress = URI(user: "+70005550101", host: "", displayName: "Example")
        let first = CallHistoryRecord(uri: sameAddress, date: Date(timeIntervalSinceReferenceDate: 42),
            duration: 12, isIncoming: true, isMissed: false, identifier: "first-uuid")
        let second = CallHistoryRecord(uri: sameAddress, date: first.date, duration: 12,
            isIncoming: true, isMissed: false, identifier: "second-uuid")
        history.add(first)
        history.add(second)
        let reopened = SQLiteCallHistory(databaseURL: url, accountUUID: "account-a")
        #expect(reopened.allRecords.map(\.identifier) == ["first-uuid", "second-uuid"])
        reopened.remove(reopened.allRecords[0])
        #expect(reopened.allRecords.map(\.identifier) == ["second-uuid"])
        let other = SQLiteCallHistory(databaseURL: url, accountUUID: "account-b")
        other.add(first)
        #expect(other.allRecords.map(\.identifier) == ["first-uuid"])
        #expect(reopened.allRecords.map(\.identifier) == ["second-uuid"])
    }

    @Test func upgradingV5RetiresAllLocalDetailsButPreservesEveryCallAndImportMarker() throws {
        let url = temporaryDatabase()
        let db = try SQLiteConnectionPool.shared.connection(at: url)

        // Synthetic v5 database. No real customer data or credentials.
        try db.execute("""
            CREATE TABLE parties(id INTEGER PRIMARY KEY, display_name TEXT)
            """)
        try db.execute("""
            CREATE TABLE calls (
                identifier TEXT NOT NULL, account_uuid TEXT NOT NULL,
                user TEXT NOT NULL, host TEXT NOT NULL, display_name TEXT NOT NULL DEFAULT '',
                date REAL NOT NULL, duration INTEGER NOT NULL, incoming INTEGER NOT NULL,
                missed INTEGER NOT NULL, party_id INTEGER,
                PRIMARY KEY(account_uuid, identifier),
                FOREIGN KEY(party_id) REFERENCES parties(id) ON DELETE SET NULL
            )
            """)
        try db.execute("""
            CREATE TABLE legacy_call_history_migrations (
                account_uuid TEXT PRIMARY KEY, source_path TEXT NOT NULL,
                imported_at REAL NOT NULL
            )
            """)
        try db.execute("INSERT INTO parties VALUES (1, 'Local draft')")
        try db.execute("""
            INSERT INTO calls VALUES
                ('shared', 'account-a', '+70005550101', '', 'Example', 42, 12, 1, 0, 1),
                ('shared', 'account-b', '+70005550102', '', 'Other', 43, 0, 1, 1, 1)
            """)
        try db.execute("""
            INSERT INTO legacy_call_history_migrations VALUES ('account-a', 'old-history.plist', 5)
            """)
        try db.execute("""
            CREATE TABLE party_notes (
                id INTEGER PRIMARY KEY, party_id INTEGER NOT NULL,
                body TEXT, FOREIGN KEY(party_id) REFERENCES parties(id) ON DELETE CASCADE
            )
            """)
        try db.execute("INSERT INTO party_notes VALUES (1, 1, 'Discard this note')")
        try db.execute("""
            CREATE TABLE party_keys (
                id INTEGER PRIMARY KEY, party_id INTEGER NOT NULL,
                FOREIGN KEY(party_id) REFERENCES parties(id) ON DELETE CASCADE
            )
            """)
        try db.execute("""
            CREATE TABLE party_addresses (
                id INTEGER PRIMARY KEY, party_id INTEGER NOT NULL,
                FOREIGN KEY(party_id) REFERENCES parties(id) ON DELETE CASCADE
            )
            """)
        for table in ["call_crm_snapshots", "party_attributes", "external_refs", "crm_sync_state"] {
            try db.execute("CREATE TABLE \(table) (value TEXT)")
        }
        try db.execute("PRAGMA user_version = 5")

        let history = SQLiteCallHistory(databaseURL: url, accountUUID: "account-a")
        let recordsA = history.allRecords
        #expect(recordsA.count == 1)
        #expect(recordsA.first?.identifier == "shared")
        #expect(recordsA.first?.uri.user == "+70005550101")
        #expect(recordsA.first?.duration == 12)
        let recordsB = SQLiteCallHistory(databaseURL: url, accountUUID: "account-b").allRecords
        #expect(recordsB.count == 1)
        #expect(recordsB.first?.isMissed == true)

        let version = try db.prepare("PRAGMA user_version")
        #expect(version.step() == SQLITE_ROW)
        #expect(version.int(at: 0) == TelephoneDatabaseSchema.currentVersion)

        let migration = try db.prepare(
            "SELECT source_path FROM legacy_call_history_migrations WHERE account_uuid='account-a'"
        )
        #expect(migration.step() == SQLITE_ROW)
        #expect(migration.string(at: 0) == "old-history.plist")

        assertOnlyHistoryTablesRemain(db)
    }

    @Test func newDatabaseContainsNoLocalCustomerStorageOrPartyColumn() throws {
        let url = temporaryDatabase()
        let history = SQLiteCallHistory(databaseURL: url, accountUUID: "account")
        history.add(CallHistoryRecord(
            uri: URI(user: "101", host: "account.invalid", displayName: ""),
            date: Date(timeIntervalSinceReferenceDate: 15), duration: 0,
            isIncoming: true, isMissed: true
        ))
        let db = try SQLiteConnectionPool.shared.connection(at: url)
        assertOnlyHistoryTablesRemain(db)
        let columns = try db.prepare("PRAGMA table_info(calls)")
        var names: [String] = []
        while columns.step() == SQLITE_ROW { names.append(columns.string(at: 1)) }
        #expect(!names.contains("party_id"))
        #expect(history.allRecords.count == 1)
    }

    private func assertOnlyHistoryTablesRemain(_ db: SQLiteConnection) {
        do {
            let statement = try db.prepare(
                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
            var names: [String] = []
            while statement.step() == SQLITE_ROW { names.append(statement.string(at: 0)) }
            #expect(names == ["calls", "legacy_call_history_migrations"])
        } catch {
            Issue.record("Could not inspect SQLite schema")
        }
    }

    private func temporaryDatabase() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite3")
    }
}
