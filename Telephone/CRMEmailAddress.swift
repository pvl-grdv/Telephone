//
//  CRMEmailAddress.swift
//  Telephone
//

import Foundation

enum CRMEmailAddress {
    // One plain ASCII mailbox, never a CRM search pattern or recipient list.
    static func normalize(_ raw: String) -> String? {
        guard raw.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return nil }
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard value.utf8.count <= 254 else { return nil }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let local = parts[0]
        let domain = parts[1]
        guard (1...64).contains(local.utf8.count), !local.hasPrefix("."),
              !local.hasSuffix("."), !local.contains(".."),
              local.utf8.allSatisfy({ isLetterOrDigit($0) || [46, 95, 43, 45].contains($0) }) else { return nil }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ label in
            (1...63).contains(label.utf8.count) && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.utf8.allSatisfy({ isLetterOrDigit($0) || $0 == 45 })
        }) else { return nil }
        return value
    }

    private static func isLetterOrDigit(_ value: UInt8) -> Bool {
        (97...122).contains(value) || (48...57).contains(value)
    }
}
