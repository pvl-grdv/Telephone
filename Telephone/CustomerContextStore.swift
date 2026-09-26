//
//  CustomerContextStore.swift
//  Telephone
//
//  Local-only customer context used to recognize prior conversations and
//  preserve notes, identifiers, and email addresses before CRM integration.
//

import Foundation
import OSLog
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

    private var connection: SQLiteConnection?

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
            customerContextLogger.error("Could not create application support directory: \(String(describing: error), privacy: .private)")
            return
        }

        let databaseURL = root.appendingPathComponent("Telephone.sqlite3")

        do {
            connection = try SQLiteConnection(url: databaseURL)
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = NORMAL")
            try execute("PRAGMA busy_timeout = 2000")
            try ensureSchema()
        } catch {
            customerContextLogger.error("Could not initialize customer context database: \(String(describing: error), privacy: .private)")
            connection = nil
        }
    }

    func load(
        address: CustomerPartyAddress,
        displayName: String,
        callIdentifier: String
    ) -> CustomerContextSnapshot {
        guard connection != nil else { return CustomerContextSnapshot() }

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
            customerContextLogger.error("Could not load customer context: \(String(describing: error), privacy: .private)")
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
        guard connection != nil else { return }

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
            customerContextLogger.error("Could not save customer context: \(String(describing: error), privacy: .private)")
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
        try bind(address.kind, at: 1, to: lookup)
        try bind(address.normalizedValue, at: 2, to: lookup)

        if lookup.step() == SQLITE_ROW {
            let partyID = lookup.int64(at: 0)
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
        try bind(displayName, at: 1, to: createParty)
        sqlite3_bind_double(
            createParty.handle,
            2,
            Date().timeIntervalSinceReferenceDate
        )
        try stepDone(createParty)

        guard let connection else {
            throw SQLiteStoreError.databaseUnavailable
        }
        let partyID = connection.lastInsertRowID

        let createAddress = try prepare(
            """
            INSERT INTO party_addresses
                (party_id, kind, value, normalized_value, label)
            VALUES (?, ?, ?, ?, '')
            """
        )
        sqlite3_bind_int64(createAddress.handle, 1, partyID)
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
        sqlite3_bind_int64(party.handle, 1, partyID)
        if party.step() == SQLITE_ROW {
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
        sqlite3_bind_int64(keys.handle, 1, partyID)
        while keys.step() == SQLITE_ROW {
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
        sqlite3_bind_int64(emails.handle, 1, partyID)
        while emails.step() == SQLITE_ROW {
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
        sqlite3_bind_int64(currentNote.handle, 1, partyID)
        try bind(callIdentifier, at: 2, to: currentNote)
        if currentNote.step() == SQLITE_ROW {
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
        sqlite3_bind_int64(recentNotes.handle, 1, partyID)
        try bind(callIdentifier, at: 2, to: recentNotes)
        while recentNotes.step() == SQLITE_ROW {
            result.recentNotes.append(
                CustomerContextNote(
                    id: recentNotes.int64(at: 0),
                    body: string(at: 1, from: recentNotes),
                    updatedAt: Date(
                        timeIntervalSinceReferenceDate:
                            recentNotes.double(at: 2)
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
            sqlite3_bind_int64(calls.handle, 1, partyID)
            if calls.step() == SQLITE_ROW {
                result.previousConversationCount = Int(calls.int64(at: 0))
                if calls.columnType(at: 1) != SQLITE_NULL {
                    result.lastCallDate = Date(
                        timeIntervalSinceReferenceDate:
                            calls.double(at: 1)
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
        try bind(displayName, at: 1, to: statement)
        try bind(displayName, at: 2, to: statement)
        if let company {
            try bind(company, at: 3, to: statement)
        } else {
            sqlite3_bind_null(statement.handle, 3)
        }
        sqlite3_bind_double(
            statement.handle,
            4,
            Date().timeIntervalSinceReferenceDate
        )
        sqlite3_bind_int64(statement.handle, 5, partyID)
        try stepDone(statement)
    }

    private func replaceKeys(
        _ values: [String],
        partyID: Int64
    ) throws {
        let delete = try prepare(
            "DELETE FROM party_keys WHERE party_id = ?"
        )
        sqlite3_bind_int64(delete.handle, 1, partyID)
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
            sqlite3_bind_int64(insert.handle, 1, partyID)
            try bind(trimmed, at: 2, to: insert)
            try bind(normalized, at: 3, to: insert)
            sqlite3_bind_double(
                insert.handle,
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
        sqlite3_bind_int64(delete.handle, 1, partyID)
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
            sqlite3_bind_int64(insert.handle, 1, partyID)
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
            sqlite3_bind_int64(delete.handle, 1, partyID)
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
        sqlite3_bind_int64(statement.handle, 1, partyID)
        try bind(callIdentifier, at: 2, to: statement)
        try bind(body, at: 3, to: statement)
        sqlite3_bind_double(statement.handle, 4, now)
        sqlite3_bind_double(statement.handle, 5, now)
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
        try bind(name, at: 1, to: statement)
        return statement.step() == SQLITE_ROW
    }

    private func transaction(_ body: () throws -> Void) throws {
        guard let connection else {
            throw SQLiteStoreError.databaseUnavailable
        }
        try connection.transaction(body)
    }

    private func execute(_ sql: String) throws {
        guard let connection else {
            throw SQLiteStoreError.databaseUnavailable
        }
        try connection.execute(sql)
    }

    private func prepare(_ sql: String) throws -> SQLiteStatement {
        guard let connection else {
            throw SQLiteStoreError.databaseUnavailable
        }
        return try connection.prepare(sql)
    }

    private func bind(
        _ value: String,
        at index: Int32,
        to statement: SQLiteStatement
    ) throws {
        try statement.bind(value, at: index)
    }

    private func stepDone(_ statement: SQLiteStatement) throws {
        try statement.stepDone()
    }

    private func string(
        at index: Int32,
        from statement: SQLiteStatement
    ) -> String {
        statement.string(at: index)
    }
}

private let customerContextLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.tlphn.Telephone",
    category: "CustomerContext"
)
