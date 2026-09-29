//
//  CallHistoryCRMStore.swift
//  Telephone
//

import Foundation
import SQLite3
import UseCases

struct StoredCallCRMCheck: Equatable, Sendable {
    let checkedAt: Date
    let status: String
    let companyID: Int?
    let companyName: String?
    let snapshotJSON: String
}

protocol CallHistoryCRMStorage: Sendable {
    func phone(accountUUID: String, callIdentifier: String) async throws -> String?
    func load(accountUUID: String, callIdentifier: String) async throws -> StoredCallCRMCheck?
    func save(
        _ check: StoredCallCRMCheck,
        accountUUID: String,
        callIdentifier: String
    ) async throws -> Bool
}

// A synchronous, stateless dependency for MainActor UI construction. Its
// database access remains on CallHistoryActor and starts only when requested.
struct DefaultCallHistoryCRMStorage: CallHistoryCRMStorage {
    func phone(accountUUID: String, callIdentifier: String) async throws -> String? {
        try await CallHistoryCRMStore.shared.phone(
            accountUUID: accountUUID, callIdentifier: callIdentifier
        )
    }

    func load(accountUUID: String, callIdentifier: String) async throws -> StoredCallCRMCheck? {
        try await CallHistoryCRMStore.shared.load(
            accountUUID: accountUUID, callIdentifier: callIdentifier
        )
    }

    func save(
        _ check: StoredCallCRMCheck,
        accountUUID: String,
        callIdentifier: String
    ) async throws -> Bool {
        try await CallHistoryCRMStore.shared.save(
            check, accountUUID: accountUUID, callIdentifier: callIdentifier
        )
    }
}

@CallHistoryActor
final class CallHistoryCRMStore: CallHistoryCRMStorage {
    static let shared = CallHistoryCRMStore()

    private let databaseURL: URL?
    private var connection: SQLiteConnection?

    // Opening the database is deferred until history has initialized its schema.
    nonisolated init(databaseURL: URL) throws {
        guard databaseURL.isFileURL else {
            throw SQLiteStoreError.sqlite("CRM history requires a local database")
        }
        self.databaseURL = databaseURL.standardizedFileURL
    }

    private nonisolated init() {
        databaseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "Telephone",
            isDirectory: true
        ).appendingPathComponent("Telephone.sqlite3")
    }

    func phone(accountUUID: String, callIdentifier: String) throws -> String? {
        try Task.checkCancellation()
        guard let connection = try readyConnection() else { return nil }
        let statement = try connection.prepare(
            "SELECT user FROM calls WHERE account_uuid = ? AND identifier = ?"
        )
        try statement.bind(accountUUID, at: 1)
        try statement.bind(callIdentifier, at: 2)
        let result = statement.step()
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else {
            throw SQLiteStoreError.sqlite("Could not read the call's original phone")
        }
        return statement.string(at: 0)
    }

    func load(accountUUID: String, callIdentifier: String) throws -> StoredCallCRMCheck? {
        try Task.checkCancellation()
        guard let connection = try readyConnection() else { return nil }
        let statement = try connection.prepare(
            """
            SELECT checked_at, status, company_id, company_name, snapshot_json
            FROM call_crm_snapshots
            WHERE account_uuid = ? AND call_identifier = ?
            """
        )
        try statement.bind(accountUUID, at: 1)
        try statement.bind(callIdentifier, at: 2)
        let result = statement.step()
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else {
            throw SQLiteStoreError.sqlite("Could not read the saved CRM check")
        }
        return StoredCallCRMCheck(
            checkedAt: Date(timeIntervalSinceReferenceDate: statement.double(at: 0)),
            status: statement.string(at: 1),
            companyID: statement.columnType(at: 2) == SQLITE_NULL
                ? nil : Int(statement.int64(at: 2)),
            companyName: statement.columnType(at: 3) == SQLITE_NULL
                ? nil : statement.string(at: 3),
            snapshotJSON: statement.string(at: 4)
        )
    }

    func save(
        _ check: StoredCallCRMCheck,
        accountUUID: String,
        callIdentifier: String
    ) throws -> Bool {
        try Task.checkCancellation()
        guard let connection = try readyConnection() else { return false }
        guard check.checkedAt.timeIntervalSinceReferenceDate.isFinite,
              !check.status.isEmpty, !check.status.contains("\0"),
              check.companyID.map({ $0 > 0 }) ?? true,
              !(check.companyName?.contains("\0") ?? false),
              !check.snapshotJSON.contains("\0") else {
            throw SQLiteStoreError.sqlite("Invalid CRM check metadata")
        }
        // Selecting the parent in this statement prevents a deleted call from
        // being recreated by an in-flight network response.
        let statement = try connection.prepare(
            """
            INSERT INTO call_crm_snapshots
                (account_uuid, call_identifier, checked_at, status,
                 company_id, company_name, snapshot_json)
            SELECT account_uuid, identifier, ?, ?, ?, ?, ?
            FROM calls
            WHERE account_uuid = ? AND identifier = ?
            ON CONFLICT(account_uuid, call_identifier) DO UPDATE SET
                checked_at = excluded.checked_at,
                status = excluded.status,
                company_id = excluded.company_id,
                company_name = excluded.company_name,
                snapshot_json = excluded.snapshot_json
            """
        )
        sqlite3_bind_double(statement.handle, 1, check.checkedAt.timeIntervalSinceReferenceDate)
        try statement.bind(check.status, at: 2)
        if let companyID = check.companyID {
            sqlite3_bind_int64(statement.handle, 3, sqlite3_int64(companyID))
        } else {
            sqlite3_bind_null(statement.handle, 3)
        }
        if let companyName = check.companyName {
            try statement.bind(companyName, at: 4)
        } else {
            sqlite3_bind_null(statement.handle, 4)
        }
        try statement.bind(check.snapshotJSON, at: 5)
        try statement.bind(accountUUID, at: 6)
        try statement.bind(callIdentifier, at: 7)
        try Task.checkCancellation()
        try statement.stepDone()
        let changes = try connection.prepare("SELECT changes()")
        guard changes.step() == SQLITE_ROW else {
            throw SQLiteStoreError.sqlite("Could not confirm the saved CRM check")
        }
        return changes.int(at: 0) != 0
    }

    private func readyConnection() throws -> SQLiteConnection? {
        guard let databaseURL else { throw SQLiteStoreError.databaseUnavailable }
        if connection == nil {
            connection = try SQLiteConnectionPool.shared.connection(at: databaseURL)
        }
        guard let connection else { throw SQLiteStoreError.databaseUnavailable }
        let versionStatement = try connection.prepare("PRAGMA user_version")
        guard versionStatement.step() == SQLITE_ROW else {
            throw SQLiteStoreError.sqlite("Could not read SQLite schema version")
        }
        let version = Int(versionStatement.int(at: 0))
        guard version <= TelephoneDatabaseSchema.currentVersion else {
            throw SQLiteStoreError.unsupportedSchema(version)
        }
        // Versions 0/1 still require history's migrations and party backfill.
        // This store must not advance their version or create any call rows.
        guard version >= 2 else { return nil }
        let parent = try connection.prepare(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'calls'"
        )
        guard parent.step() == SQLITE_ROW else { return nil }
        if version == 2 {
            try connection.transaction {
                try TelephoneDatabaseSchema.createCallCRMSnapshotTable(execute: connection.execute)
                try connection.execute("PRAGMA user_version = 3")
            }
        } else {
            try TelephoneDatabaseSchema.createCallCRMSnapshotTable(execute: connection.execute)
        }
        return connection
    }
}
