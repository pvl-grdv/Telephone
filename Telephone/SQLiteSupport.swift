//
//  SQLiteSupport.swift
//  Telephone
//

import Foundation
import SQLite3

enum SQLiteStoreError: Error, CustomStringConvertible {
    case databaseUnavailable
    case unsupportedSchema(Int)
    case invalidLegacyCallHistory
    case sqlite(String)

    var description: String {
        switch self {
        case .databaseUnavailable:
            return "SQLite database is unavailable"
        case let .unsupportedSchema(version):
            return "SQLite schema version \(version) is newer than this Telephone build supports"
        case .invalidLegacyCallHistory:
            return "Legacy call history has an unexpected format"
        case let .sqlite(message):
            return message
        }
    }
}

final class SQLiteConnection {
    private let handle: OpaquePointer

    init(url: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard result == SQLITE_OK, let database else {
            let message = database.map {
                String(cString: sqlite3_errmsg($0))
            } ?? "Unknown SQLite error"
            sqlite3_close(database)
            throw SQLiteStoreError.sqlite(message)
        }

        handle = database
    }

    deinit {
        sqlite3_close(handle)
    }

    var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(
            handle,
            sql,
            nil,
            nil,
            &errorMessage
        )

        guard result == SQLITE_OK else {
            let message = errorMessage.map {
                String(cString: $0)
            } ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(errorMessage)
            throw SQLiteStoreError.sqlite(message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        try SQLiteStatement(database: handle, sql: sql)
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
}

final class SQLiteStatement {
    let handle: OpaquePointer
    private let database: OpaquePointer

    init(database: OpaquePointer, sql: String) throws {
        self.database = database

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
            throw SQLiteStoreError.sqlite(
                String(cString: sqlite3_errmsg(database))
            )
        }

        handle = statement
    }

    deinit {
        sqlite3_finalize(handle)
    }

    func bind(_ value: String, at index: Int32) throws {
        let result = value.withCString {
            sqlite3_bind_text(
                handle,
                index,
                $0,
                -1,
                sqliteTransient
            )
        }
        guard result == SQLITE_OK else {
            throw SQLiteStoreError.sqlite(
                String(cString: sqlite3_errmsg(database))
            )
        }
    }

    func step() -> Int32 {
        sqlite3_step(handle)
    }

    func stepDone() throws {
        guard step() == SQLITE_DONE else {
            throw SQLiteStoreError.sqlite(
                String(cString: sqlite3_errmsg(database))
            )
        }
    }

    func string(at index: Int32) -> String {
        guard let value = sqlite3_column_text(handle, index) else {
            return ""
        }
        return String(cString: value)
    }

    func int64(at index: Int32) -> Int64 {
        sqlite3_column_int64(handle, index)
    }

    func int(at index: Int32) -> Int32 {
        sqlite3_column_int(handle, index)
    }

    func double(at index: Int32) -> Double {
        sqlite3_column_double(handle, index)
    }

    func columnType(at index: Int32) -> Int32 {
        sqlite3_column_type(handle, index)
    }
}

private let sqliteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
