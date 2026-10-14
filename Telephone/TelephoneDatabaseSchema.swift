//
//  TelephoneDatabaseSchema.swift
//  Telephone
//

import SQLite3
import UseCases

enum TelephoneDatabaseSchema {
    static let currentVersion = 5

    // Version 5 retires unused CRM-history snapshots and old CRM sync
    // scaffolding. Calls, local customer details and historical user notes
    // remain intact. Run this inside the call-history migration transaction.
    static func removeUnusedTables(execute: (String) throws -> Void) throws {
        try execute("DROP TABLE IF EXISTS call_crm_snapshots")
        try execute("DROP TABLE IF EXISTS external_refs")
        try execute("DROP TABLE IF EXISTS party_attributes")
        try execute("DROP TABLE IF EXISTS crm_sync_state")
    }

    static func createPartyTables(
        execute: (String) throws -> Void
    ) throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS parties (
                id INTEGER PRIMARY KEY,
                display_name TEXT NOT NULL DEFAULT '',
                company TEXT NOT NULL DEFAULT '',
                updated_at REAL NOT NULL DEFAULT 0
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS party_addresses (
                id INTEGER PRIMARY KEY,
                party_id INTEGER NOT NULL,
                kind TEXT NOT NULL,
                value TEXT NOT NULL,
                normalized_value TEXT NOT NULL,
                label TEXT NOT NULL DEFAULT '',
                FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
                UNIQUE (kind, normalized_value)
            )
            """
        )

    }

    static func createCustomerContextTables(
        execute: (String) throws -> Void
    ) throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS party_notes (
                id INTEGER PRIMARY KEY,
                party_id INTEGER NOT NULL,
                account_uuid TEXT NOT NULL DEFAULT '',
                call_identifier TEXT NOT NULL,
                body TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
                UNIQUE (party_id, account_uuid, call_identifier)
            )
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS party_notes_party_date
            ON party_notes(party_id, updated_at DESC)
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS party_keys (
                id INTEGER PRIMARY KEY,
                party_id INTEGER NOT NULL,
                value TEXT NOT NULL,
                normalized_value TEXT NOT NULL,
                created_at REAL NOT NULL,
                FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
                UNIQUE (party_id, normalized_value)
            )
            """
        )
    }

    // A note can precede its completed call row. No calls foreign key is added:
    // deleting call history deliberately retains historical customer notes.
    // Legacy notes have no reliable call/account identity and remain unmatched.
    @CallHistoryActor
    static func migrateCustomerContextTables(connection: SQLiteConnection) throws {
        try createCustomerContextTables(execute: connection.execute)
        let columns = try connection.prepare("PRAGMA table_info(party_notes)")
        var hasAccount = false
        while columns.step() == SQLITE_ROW {
            if columns.string(at: 1) == "account_uuid" { hasAccount = true }
        }
        if hasAccount {
            try connection.execute("CREATE INDEX IF NOT EXISTS party_notes_call ON party_notes(account_uuid, call_identifier)")
            return
        }
        try connection.execute("ALTER TABLE party_notes RENAME TO legacy_party_notes")
        try createCustomerContextTables(execute: connection.execute)
        try connection.execute(
            """
            INSERT INTO party_notes(id, party_id, account_uuid, call_identifier, body, created_at, updated_at)
            SELECT id, party_id, '', call_identifier, body, created_at, updated_at
            FROM legacy_party_notes
            """
        )
        try connection.execute("DROP TABLE legacy_party_notes")
        // The previous index name belonged to the renamed table until DROP.
        try connection.execute("CREATE INDEX IF NOT EXISTS party_notes_party_date ON party_notes(party_id, updated_at DESC)")
        try connection.execute("CREATE INDEX IF NOT EXISTS party_notes_call ON party_notes(account_uuid, call_identifier)")
    }
}
