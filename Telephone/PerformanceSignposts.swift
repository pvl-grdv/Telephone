//
//  PerformanceSignposts.swift
//  Telephone
//

import OSLog

enum PerformanceSignposts {
    static let settings = OSSignposter(logger: Log.settingsPerformance)
    static let contacts = OSSignposter(logger: Log.contactsPerformance)
    static let calls = OSSignposter(logger: Log.callPerformance)
}
