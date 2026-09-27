//
//  Logging.swift
//  Telephone
//

import OSLog

enum Log {
    private static let subsystem = "com.tlphn.Telephone"

    static let contacts = Logger(
        subsystem: subsystem,
        category: "Contacts"
    )

    static let callDestination = Logger(
        subsystem: subsystem,
        category: "CallDestination"
    )

    static let customerContext = Logger(
        subsystem: subsystem,
        category: "CustomerContext"
    )

    static let callHistory = Logger(
        subsystem: subsystem,
        category: "CallHistory"
    )

    static let settingsPerformance = Logger(
        subsystem: subsystem,
        category: "SettingsPerformance"
    )

    static let contactsPerformance = Logger(
        subsystem: subsystem,
        category: "ContactsPerformance"
    )

    static let callPerformance = Logger(
        subsystem: subsystem,
        category: "CallPerformance"
    )

    static let databasePerformance = Logger(
        subsystem: subsystem,
        category: "DatabasePerformance"
    )
}
