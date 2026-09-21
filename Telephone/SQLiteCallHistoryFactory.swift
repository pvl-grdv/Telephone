//
//  SQLiteCallHistoryFactory.swift
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
import UseCases

@CallHistoryActor
final class SQLiteCallHistoryFactory: CallHistoryFactory {
    private let locations: ApplicationDataLocations

    nonisolated init(locations: ApplicationDataLocations) {
        self.locations = locations
    }

    func make(uuid: String) -> CallHistory {
        let history = SQLiteCallHistory(
            databaseURL: locations.root().appendingPathComponent("Telephone.sqlite3"),
            accountUUID: uuid
        )

        // Keep the original plist untouched as a rollback/forensics backup.
        // A migration marker in SQLite makes the import idempotent.
        history.migrateLegacyPropertyList(
            at: locations.callHistories().appendingPathComponent("\(uuid).plist")
        )
        return history
    }
}
