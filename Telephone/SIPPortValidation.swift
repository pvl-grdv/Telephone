//
//  SIPPortValidation.swift
//  Telephone
//

import Foundation

enum SIPPortValidation {
    static let range = 1...65_535

    static func value(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return 0
        }
        guard let value = Int(trimmed), range.contains(value) else {
            return nil
        }
        return value
    }

    static func isValid(_ text: String) -> Bool {
        value(text) != nil
    }
}
