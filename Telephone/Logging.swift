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

    static let performance = Logger(
        subsystem: subsystem,
        category: "Performance"
    )

    static let sip = Logger(subsystem: subsystem, category: "SIP")
    static let application = Logger(subsystem: subsystem, category: "Application")
    static let audio = Logger(subsystem: subsystem, category: "Audio")
    static let storage = Logger(subsystem: subsystem, category: "Storage")
    static let systemIntegration = Logger(
        subsystem: subsystem,
        category: "SystemIntegration"
    )
    static let media = Logger(subsystem: subsystem, category: "Media")
}
