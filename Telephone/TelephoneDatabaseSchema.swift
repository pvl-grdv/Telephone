//
//  TelephoneDatabaseSchema.swift
//  Telephone
//

enum TelephoneDatabaseSchema {
    static let currentVersion = 2

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
        try execute(
            """
            CREATE TABLE IF NOT EXISTS party_attributes (
                party_id INTEGER NOT NULL,
                key TEXT NOT NULL,
                value TEXT NOT NULL,
                PRIMARY KEY (party_id, key),
                FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS external_refs (
                party_id INTEGER NOT NULL,
                provider TEXT NOT NULL,
                external_id TEXT NOT NULL,
                PRIMARY KEY (provider, external_id),
                FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS crm_sync_state (
                provider TEXT PRIMARY KEY,
                cursor TEXT,
                last_sync REAL,
                last_error TEXT
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
                call_identifier TEXT NOT NULL,
                body TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
                UNIQUE (party_id, call_identifier)
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
}
