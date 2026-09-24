//
//  CallWindowCloseNotificationGate.swift
//  Telephone
//

struct CallWindowCloseNotificationGate {
    private(set) var hasNotified = false

    mutating func reset() {
        hasNotified = false
    }

    mutating func consume() -> Bool {
        guard !hasNotified else {
            return false
        }

        hasNotified = true
        return true
    }
}
