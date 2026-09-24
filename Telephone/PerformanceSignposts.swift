//
//  PerformanceSignposts.swift
//  Telephone
//

import Foundation
import OSLog

enum PerformanceSignposts {
    private static let subsystem =
        Bundle.main.bundleIdentifier ?? "com.tlphn.Telephone"

    static let settings = OSSignposter(
        logger: Logger(
            subsystem: subsystem,
            category: "SettingsPerformance"
        )
    )

    static let contacts = OSSignposter(
        logger: Logger(
            subsystem: subsystem,
            category: "ContactsPerformance"
        )
    )

    static let calls = OSSignposter(
        logger: Logger(
            subsystem: subsystem,
            category: "CallPerformance"
        )
    )
}
