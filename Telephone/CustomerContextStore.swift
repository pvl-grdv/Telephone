//
//  CustomerContextStore.swift
//  Telephone
//
//  Local-only customer context used to recognize prior conversations and
//  preserve notes, identifiers, and email addresses before CRM integration.
//

import Foundation
import SQLite3
import UseCases

struct CustomerContextNote: Identifiable, Sendable {
    let id: Int64
    let body: String
    let updatedAt: Date
}

struct CustomerContextSnapshot: Sendable {
    var company = ""
    var keys: [String] = []
    var emails: [String] = []
    var currentCallNote = ""
    var recentNotes: [CustomerContextNote] = []
    var previousConversationCount = 0
    var lastCallDate: Date?
}

@CallHistoryActor
final class CustomerContextStore {
    static let shared = CustomerContextStore()

    private nonisolated(unsafe) var database: OpaquePointer?

    private init() {
        let manager = FileManager.default
        guard let applicationSupport = manager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return
        }

        let root = applicationSupport.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "Telephone",
            isDirectory: true
        )

        do {
            try manager.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        } catch {
            NSLog("Could not create Telephone application support directory: %@", String(describing: error))
            return
        }

        let databaseURL = root.appendingPathComponent("Telephone.sqlite3")
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            let message = database.map {
                String(cString: sqlite3_errmsg($0))
            } ?? "Unknown SQLite error"
            NSLog("Could not open customer context database: %@", message)
            sqlite3_close(database)
            database = nil
            return
        }

        do {
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = NORMAL")
            try execute("PRAGMA busy_timeout = 2000")
            try ensureSchema()
        } catch {
            NSLog("Could not initialize customer context database: %@", String(describing: error))
        }
    }

    deinit {
        sqlite3_close(database)
    }

    func load(
        address: CustomerPartyAddress,
        displayName: String,
        callIdentifier: String
    ) -> CustomerContextSnapshot {
        guard database != nil else { return CustomerContextSnapshot() }

        do {
            let partyID = try ensureParty(
                address: address,
                displayName: displayName
            )
            return try snapshot(
                partyID: partyID,
                callIdentifier: callIdentifier
            )
        } catch {
            NSLog("Could not load customer context: %@", String(describing: error))
            return CustomerContextSnapshot()
        }
    }

    func save(
        address: CustomerPartyAddress,
        displayName: String,
        callIdentifier: String,
        company: String,
        keys: [String],
        emails: [String],
        note: String
    ) {
        guard database != nil else { return }

        do {
            let partyID = try ensureParty(
                address: address,
                displayName: displayName
            )

            try transaction {
                try updateParty(
                    partyID: partyID,
                    displayName: displayName,
                    company: company
                )
                try replaceKeys(keys, partyID: partyID)
                try replaceEmails(emails, partyID: partyID)
                try saveNote(
                    note,
                    partyID: partyID,
                    callIdentifier: callIdentifier
                )
            }
        } catch {
            NSLog("Could not save customer context: %@", String(describing: error))
        }
    }

    private func ensureSchema() throws {
        try TelephoneDatabaseSchema.createPartyTables(execute: execute)
        try TelephoneDatabaseSchema.createCustomerContextTables(
            execute: execute
        )
    }

    private func ensureParty(
        address: CustomerPartyAddress,
        displayName: String
    ) throws -> Int64 {
        let lookup = try prepare(
            """
            SELECT party_id
            FROM party_addresses
            WHERE kind = ? AND normalized_value = ?
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(lookup) }
        try bind(address.kind, at: 1, to: lookup)
        try bind(address.normalizedValue, at: 2, to: lookup)

        if sqlite3_step(lookup) == SQLITE_ROW {
            let partyID = sqlite3_column_int64(lookup, 0)
            if !displayName.isEmpty {
                try updateParty(
                    partyID: partyID,
                    displayName: displayName,
                    company: nil
                )
            }
            return partyID
        }

        let createParty = try prepare(
            "INSERT INTO parties (display_name, updated_at) VALUES (?, ?)"
        )
        defer { sqlite3_finalize(createParty) }
        try bind(displayName, at: 1, to: createParty)
        sqlite3_bind_double(
            createParty,
            2,
            Date().timeIntervalSinceReferenceDate
        )
        try stepDone(createParty)

        guard let database else {
            throw CustomerContextStoreError.databaseUnavailable
        }
        let partyID = sqlite3_last_insert_rowid(database)

        let createAddress = try prepare(
            """
            INSERT INTO party_addresses
                (party_id, kind, value, normalized_value, label)
            VALUES (?, ?, ?, ?, '')
            """
        )
        defer { sqlite3_finalize(createAddress) }
        sqlite3_bind_int64(createAddress, 1, partyID)
        try bind(address.kind, at: 2, to: createAddress)
        try bind(address.value, at: 3, to: createAddress)
        try bind(address.normalizedValue, at: 4, to: createAddress)
        try stepDone(createAddress)

        return partyID
    }

    private func snapshot(
        partyID: Int64,
        callIdentifier: String
    ) throws -> CustomerContextSnapshot {
        var result = CustomerContextSnapshot()

        let party = try prepare(
            "SELECT company FROM parties WHERE id = ?"
        )
        defer { sqlite3_finalize(party) }
        sqlite3_bind_int64(party, 1, partyID)
        if sqlite3_step(party) == SQLITE_ROW {
            result.company = string(at: 0, from: party)
        }

        let keys = try prepare(
            """
            SELECT value
            FROM party_keys
            WHERE party_id = ?
            ORDER BY id ASC
            """
        )
        defer { sqlite3_finalize(keys) }
        sqlite3_bind_int64(keys, 1, partyID)
        while sqlite3_step(keys) == SQLITE_ROW {
            result.keys.append(string(at: 0, from: keys))
        }

        let emails = try prepare(
            """
            SELECT value
            FROM party_addresses
            WHERE party_id = ? AND kind = 'email'
            ORDER BY id ASC
            """
        )
        defer { sqlite3_finalize(emails) }
        sqlite3_bind_int64(emails, 1, partyID)
        while sqlite3_step(emails) == SQLITE_ROW {
            result.emails.append(string(at: 0, from: emails))
        }

        let currentNote = try prepare(
            """
            SELECT body
            FROM party_notes
            WHERE party_id = ? AND call_identifier = ?
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(currentNote) }
        sqlite3_bind_int64(currentNote, 1, partyID)
        try bind(callIdentifier, at: 2, to: currentNote)
        if sqlite3_step(currentNote) == SQLITE_ROW {
            result.currentCallNote = string(at: 0, from: currentNote)
        }

        let recentNotes = try prepare(
            """
            SELECT id, body, updated_at
            FROM party_notes
            WHERE party_id = ?
              AND call_identifier <> ?
              AND TRIM(body) <> ''
            ORDER BY updated_at DESC
            LIMIT 3
            """
        )
        defer { sqlite3_finalize(recentNotes) }
        sqlite3_bind_int64(recentNotes, 1, partyID)
        try bind(callIdentifier, at: 2, to: recentNotes)
        while sqlite3_step(recentNotes) == SQLITE_ROW {
            result.recentNotes.append(
                CustomerContextNote(
                    id: sqlite3_column_int64(recentNotes, 0),
                    body: string(at: 1, from: recentNotes),
                    updatedAt: Date(
                        timeIntervalSinceReferenceDate:
                            sqlite3_column_double(recentNotes, 2)
                    )
                )
            )
        }

        if try tableExists("calls") {
            let calls = try prepare(
                """
                SELECT COUNT(*), MAX(date)
                FROM calls
                WHERE party_id = ? AND duration > 0
                """
            )
            defer { sqlite3_finalize(calls) }
            sqlite3_bind_int64(calls, 1, partyID)
            if sqlite3_step(calls) == SQLITE_ROW {
                result.previousConversationCount = Int(sqlite3_column_int64(calls, 0))
                if sqlite3_column_type(calls, 1) != SQLITE_NULL {
                    result.lastCallDate = Date(
                        timeIntervalSinceReferenceDate:
                            sqlite3_column_double(calls, 1)
                    )
                }
            }
        }

        return result
    }

    private func updateParty(
        partyID: Int64,
        displayName: String,
        company: String?
    ) throws {
        let statement = try prepare(
            """
            UPDATE parties
            SET display_name = CASE
                    WHEN ? <> '' THEN ?
                    ELSE display_name
                END,
                company = COALESCE(?, company),
                updated_at = ?
            WHERE id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(displayName, at: 1, to: statement)
        try bind(displayName, at: 2, to: statement)
        if let company {
            try bind(company, at: 3, to: statement)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        sqlite3_bind_double(
            statement,
            4,
            Date().timeIntervalSinceReferenceDate
        )
        sqlite3_bind_int64(statement, 5, partyID)
        try stepDone(statement)
    }

    private func replaceKeys(
        _ values: [String],
        partyID: Int64
    ) throws {
        let delete = try prepare(
            "DELETE FROM party_keys WHERE party_id = ?"
        )
        defer { sqlite3_finalize(delete) }
        sqlite3_bind_int64(delete, 1, partyID)
        try stepDone(delete)

        var seen = Set<String>()
        for value in values {
            let trimmed = value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let normalized = trimmed.lowercased()
            guard !trimmed.isEmpty, seen.insert(normalized).inserted else {
                continue
            }

            let insert = try prepare(
                """
                INSERT INTO party_keys
                    (party_id, value, normalized_value, created_at)
                VALUES (?, ?, ?, ?)
                """
            )
            defer { sqlite3_finalize(insert) }
            sqlite3_bind_int64(insert, 1, partyID)
            try bind(trimmed, at: 2, to: insert)
            try bind(normalized, at: 3, to: insert)
            sqlite3_bind_double(
                insert,
                4,
                Date().timeIntervalSinceReferenceDate
            )
            try stepDone(insert)
        }
    }

    private func replaceEmails(
        _ values: [String],
        partyID: Int64
    ) throws {
        let delete = try prepare(
            "DELETE FROM party_addresses WHERE party_id = ? AND kind = 'email'"
        )
        defer { sqlite3_finalize(delete) }
        sqlite3_bind_int64(delete, 1, partyID)
        try stepDone(delete)

        var seen = Set<String>()
        for value in values {
            let address = CustomerPartyAddress(email: value)
            guard
                !address.value.isEmpty,
                address.value.contains("@"),
                seen.insert(address.normalizedValue).inserted
            else {
                continue
            }

            let insert = try prepare(
                """
                INSERT OR IGNORE INTO party_addresses
                    (party_id, kind, value, normalized_value, label)
                VALUES (?, ?, ?, ?, '')
                """
            )
            defer { sqlite3_finalize(insert) }
            sqlite3_bind_int64(insert, 1, partyID)
            try bind(address.kind, at: 2, to: insert)
            try bind(address.value, at: 3, to: insert)
            try bind(address.normalizedValue, at: 4, to: insert)
            try stepDone(insert)
        }
    }

    private func saveNote(
        _ value: String,
        partyID: Int64,
        callIdentifier: String
    ) throws {
        let body = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            let delete = try prepare(
                """
                DELETE FROM party_notes
                WHERE party_id = ? AND call_identifier = ?
                """
            )
            defer { sqlite3_finalize(delete) }
            sqlite3_bind_int64(delete, 1, partyID)
            try bind(callIdentifier, at: 2, to: delete)
            try stepDone(delete)
            return
        }

        let now = Date().timeIntervalSinceReferenceDate
        let statement = try prepare(
            """
            INSERT INTO party_notes
                (
                    party_id,
                    call_identifier,
                    body,
                    created_at,
                    updated_at
                )
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(party_id, call_identifier) DO UPDATE SET
                body = excluded.body,
                updated_at = excluded.updated_at
            """
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, partyID)
        try bind(callIdentifier, at: 2, to: statement)
        try bind(body, at: 3, to: statement)
        sqlite3_bind_double(statement, 4, now)
        sqlite3_bind_double(statement, 5, now)
        try stepDone(statement)
    }

    private func tableExists(_ name: String) throws -> Bool {
        let statement = try prepare(
            """
            SELECT 1
            FROM sqlite_master
            WHERE type = 'table' AND name = ?
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(name, at: 1, to: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        guard let database else {
            throw CustomerContextStoreError.databaseUnavailable
        }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(
            database,
            sql,
            nil,
            nil,
            &errorMessage
        )
        guard result == SQLITE_OK else {
            let message = errorMessage.map {
                String(cString: $0)
            } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw CustomerContextStoreError.sqlite(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else {
            throw CustomerContextStoreError.databaseUnavailable
        }

        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                database,
                sql,
                -1,
                &statement,
                nil
            ) == SQLITE_OK,
            let statement
        else {
            throw CustomerContextStoreError.sqlite(
                String(cString: sqlite3_errmsg(database))
            )
        }
        return statement
    }

    private func bind(
        _ value: String,
        at index: Int32,
        to statement: OpaquePointer
    ) throws {
        let result = value.withCString {
            sqlite3_bind_text(
                statement,
                index,
                $0,
                -1,
                customerContextSQLiteTransient
            )
        }
        guard result == SQLITE_OK else {
            throw CustomerContextStoreError.sqlite(
                database.map {
                    String(cString: sqlite3_errmsg($0))
                } ?? "Bind failed"
            )
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CustomerContextStoreError.sqlite(
                database.map {
                    String(cString: sqlite3_errmsg($0))
                } ?? "SQLite step failed"
            )
        }
    }

    private func string(
        at index: Int32,
        from statement: OpaquePointer
    ) -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: value)
    }
}

private enum CustomerContextStoreError: Error, CustomStringConvertible {
    case databaseUnavailable
    case sqlite(String)

    var description: String {
        switch self {
        case .databaseUnavailable:
            return "Customer context database is unavailable"
        case let .sqlite(message):
            return message
        }
    }
}

private let customerContextSQLiteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
