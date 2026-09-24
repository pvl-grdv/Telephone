//
//  SQLiteCallHistory.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//  Modifications © 2026 Pavel Gordeev
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import Foundation
import SQLite3
import UseCases

@CallHistoryActor
final class SQLiteCallHistory {
    private let accountUUID: String
    private nonisolated(unsafe) var database: OpaquePointer?

    init(databaseURL: URL, accountUUID: String) {
        self.accountUUID = accountUUID

        if sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) != SQLITE_OK {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            NSLog("Could not open call history database: %@", message)
            sqlite3_close(database)
            database = nil
            return
        }

        do {
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = NORMAL")
            try execute("PRAGMA busy_timeout = 2000")
            try migrateSchema()
        } catch {
            NSLog("Could not initialize call history database: %@", String(describing: error))
        }
    }

    deinit {
        sqlite3_close(database)
    }

    func migrateLegacyPropertyList(at url: URL) {
        guard database != nil, FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            if try hasMigrationMarker(for: url) {
                return
            }

            let records = try legacyRecords(at: url)
            try transaction {
                for record in records {
                    try insert(record)
                }
                try markMigrated(url)
            }
            NSLog("Migrated %ld call history records from %@", records.count, url.path)
        } catch {
            NSLog("Could not migrate legacy call history %@: %@", url.path, String(describing: error))
        }
    }
}

extension SQLiteCallHistory: CallHistory {
    var allRecords: [CallHistoryRecord] {
        guard database != nil else { return [] }

        let sql = """
        SELECT user, host, display_name, date, duration, incoming, missed
        FROM calls
        WHERE account_uuid = ?
        ORDER BY date ASC, rowid ASC
        """

        do {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(accountUUID, at: 1, to: statement)

            var result: [CallHistoryRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let user = string(at: 0, from: statement)
                let host = string(at: 1, from: statement)
                let displayName = string(at: 2, from: statement)
                let date = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 3))
                let duration = Int(sqlite3_column_int64(statement, 4))
                let incoming = sqlite3_column_int(statement, 5) != 0
                let missed = sqlite3_column_int(statement, 6) != 0

                result.append(
                    CallHistoryRecord(
                        uri: URI(user: user, host: host, displayName: displayName),
                        date: date,
                        duration: duration,
                        isIncoming: incoming,
                        isMissed: missed
                    )
                )
            }
            return result
        } catch {
            NSLog("Could not read call history: %@", String(describing: error))
            return []
        }
    }

    func add(_ record: CallHistoryRecord) {
        do {
            try insert(record)
        } catch {
            NSLog("Could not add call history record: %@", String(describing: error))
        }
    }

    func remove(_ record: CallHistoryRecord) {
        do {
            let statement = try prepare("DELETE FROM calls WHERE account_uuid = ? AND identifier = ?")
            defer { sqlite3_finalize(statement) }
            try bind(accountUUID, at: 1, to: statement)
            try bind(record.identifier, at: 2, to: statement)
            try stepDone(statement)
        } catch {
            NSLog("Could not remove call history record: %@", String(describing: error))
        }
    }

    func removeAll() {
        do {
            let statement = try prepare("DELETE FROM calls WHERE account_uuid = ?")
            defer { sqlite3_finalize(statement) }
            try bind(accountUUID, at: 1, to: statement)
            try stepDone(statement)
        } catch {
            NSLog("Could not remove call history: %@", String(describing: error))
        }
    }

    func updateTarget(_ target: CallHistoryEventTarget) {}
}

private extension SQLiteCallHistory {
    static let schemaVersion = 2

    func migrateSchema() throws {
        var version = try userVersion()
        guard version <= Self.schemaVersion else {
            throw SQLiteCallHistoryError.unsupportedSchema(version)
        }

        if version == 0 {
            try transaction {
                try createSchemaVersion1()
                try execute("PRAGMA user_version = 1")
            }
            version = 1
        }

        if version < 2 {
            try transaction {
                try createSchemaVersion2()
                try backfillCallParties()
                try execute("PRAGMA user_version = 2")
            }
        }
    }

    func userVersion() throws -> Int {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteCallHistoryError.sqlite("Could not read SQLite schema version")
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    func createSchemaVersion1() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS calls (
                identifier TEXT NOT NULL,
                account_uuid TEXT NOT NULL,
                user TEXT NOT NULL,
                host TEXT NOT NULL,
                display_name TEXT NOT NULL DEFAULT '',
                date REAL NOT NULL,
                duration INTEGER NOT NULL,
                incoming INTEGER NOT NULL,
                missed INTEGER NOT NULL,
                party_id INTEGER,
                PRIMARY KEY (account_uuid, identifier),
                FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE SET NULL
            )
            """
        )
        try execute("CREATE INDEX IF NOT EXISTS calls_account_date ON calls(account_uuid, date DESC)")
        try execute("CREATE INDEX IF NOT EXISTS calls_account_user ON calls(account_uuid, user)")

        try TelephoneDatabaseSchema.createPartyTables(execute: execute)
        try execute(
            """
            CREATE TABLE IF NOT EXISTS legacy_call_history_migrations (
                account_uuid TEXT PRIMARY KEY,
                source_path TEXT NOT NULL,
                imported_at REAL NOT NULL
            )
            """
        )
    }

    func createSchemaVersion2() throws {
        try TelephoneDatabaseSchema.createCustomerContextTables(
            execute: execute
        )
    }

    func backfillCallParties() throws {
        let statement = try prepare(
            """
            SELECT rowid, user, host, display_name
            FROM calls
            WHERE party_id IS NULL
            """
        )
        defer { sqlite3_finalize(statement) }

        var pending: [(rowID: Int64, partyID: Int64)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(statement, 0)
            let user = string(at: 1, from: statement)
            let host = string(at: 2, from: statement)
            let displayName = string(at: 3, from: statement)
            let partyID = try ensureParty(
                user: user,
                host: host,
                displayName: displayName
            )
            pending.append((rowID, partyID))
        }

        for item in pending {
            let update = try prepare(
                "UPDATE calls SET party_id = ? WHERE rowid = ?"
            )
            defer { sqlite3_finalize(update) }
            sqlite3_bind_int64(update, 1, item.partyID)
            sqlite3_bind_int64(update, 2, item.rowID)
            try stepDone(update)
        }
    }

    func ensureParty(
        user: String,
        host: String,
        displayName: String
    ) throws -> Int64 {
        let address = CustomerPartyAddress(user: user, host: host)

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
                let update = try prepare(
                    """
                    UPDATE parties
                    SET display_name = CASE
                        WHEN display_name = '' THEN ?
                        ELSE display_name
                    END,
                    updated_at = ?
                    WHERE id = ?
                    """
                )
                defer { sqlite3_finalize(update) }
                try bind(displayName, at: 1, to: update)
                sqlite3_bind_double(update, 2, Date().timeIntervalSinceReferenceDate)
                sqlite3_bind_int64(update, 3, partyID)
                try stepDone(update)
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
            throw SQLiteCallHistoryError.databaseUnavailable
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

    func insert(_ record: CallHistoryRecord) throws {
        let partyID = try ensureParty(
            user: record.uri.user,
            host: record.uri.host,
            displayName: record.uri.displayName
        )
        let statement = try prepare(
            """
            INSERT OR IGNORE INTO calls
                (
                    identifier,
                    account_uuid,
                    user,
                    host,
                    display_name,
                    date,
                    duration,
                    incoming,
                    missed,
                    party_id
                )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(record.identifier, at: 1, to: statement)
        try bind(accountUUID, at: 2, to: statement)
        try bind(record.uri.user, at: 3, to: statement)
        try bind(record.uri.host, at: 4, to: statement)
        try bind(record.uri.displayName, at: 5, to: statement)
        sqlite3_bind_double(statement, 6, record.date.timeIntervalSinceReferenceDate)
        sqlite3_bind_int64(statement, 7, sqlite3_int64(record.duration))
        sqlite3_bind_int(statement, 8, record.isIncoming ? 1 : 0)
        sqlite3_bind_int(statement, 9, record.isMissed ? 1 : 0)
        sqlite3_bind_int64(statement, 10, partyID)

        try stepDone(statement)
    }

    func hasMigrationMarker(for url: URL) throws -> Bool {
        let statement = try prepare(
            "SELECT 1 FROM legacy_call_history_migrations WHERE account_uuid = ? LIMIT 1"
        )
        defer { sqlite3_finalize(statement) }
        try bind(accountUUID, at: 1, to: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    func markMigrated(_ url: URL) throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO legacy_call_history_migrations
                (account_uuid, source_path, imported_at)
            VALUES (?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(accountUUID, at: 1, to: statement)
        try bind(url.path, at: 2, to: statement)
        sqlite3_bind_double(statement, 3, Date().timeIntervalSinceReferenceDate)
        try stepDone(statement)
    }

    func legacyRecords(at url: URL) throws -> [CallHistoryRecord] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionaries = plist as? [[String: Any]] else { return [] }

        return dictionaries.map {
            CallHistoryRecord(
                uri: URI(
                    user: $0["user"] as? String ?? "",
                    host: $0["host"] as? String ?? "",
                    displayName: $0["name"] as? String ?? ""
                ),
                date: $0["date"] as? Date ?? Date.distantPast,
                duration: $0["duration"] as? Int ?? 0,
                isIncoming: $0["incoming"] as? Bool ?? false,
                isMissed: $0["missed"] as? Bool ?? false
            )
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func execute(_ sql: String) throws {
        guard let database else { throw SQLiteCallHistoryError.databaseUnavailable }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw SQLiteCallHistoryError.sqlite(message)
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw SQLiteCallHistoryError.databaseUnavailable }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteCallHistoryError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    func bind(_ value: String, at index: Int32, to statement: OpaquePointer) throws {
        let result = value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
        }
        guard result == SQLITE_OK else {
            throw SQLiteCallHistoryError.sqlite(database.map { String(cString: sqlite3_errmsg($0)) } ?? "Bind failed")
        }
    }

    func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteCallHistoryError.sqlite(database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite step failed")
        }
    }

    func string(at index: Int32, from statement: OpaquePointer) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }
}


private enum SQLiteCallHistoryError: Error, CustomStringConvertible {
    case databaseUnavailable
    case unsupportedSchema(Int)
    case sqlite(String)

    var description: String {
        switch self {
        case .databaseUnavailable:
            return "SQLite database is unavailable"
        case let .unsupportedSchema(version):
            return "SQLite schema version \(version) is newer than this Telephone build supports"
        case let .sqlite(message):
            return message
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
