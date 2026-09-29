//
//  CRMPhoneNumber.swift
//  Telephone
//

import Foundation

enum CRMPhoneNumber {
    static func normalize(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        var digits = ""
        for (index, scalar) in value.unicodeScalars.enumerated() {
            switch scalar.value {
            case 48...57: digits.unicodeScalars.append(scalar)
            case 43: guard index == 0 else { return nil }
            case 32, 160, 40, 41, 45, 46: break
            default: return nil
            }
        }
        let explicitInternational = value.first == "+"
        if !explicitInternational, digits.count == 10 { digits = "7" + digits }
        if !explicitInternational, digits.count == 11, digits.first == "8" {
            digits = "7" + String(digits.dropFirst())
        }
        guard (8...15).contains(digits.count), digits.first != "0" else { return nil }
        return "+" + digits
    }

    static func contains(_ phone: String, in rawField: String) -> Bool {
        guard let target = normalize(phone) else { return false }
        return rawField.components(separatedBy: CharacterSet(charactersIn: ",;\n\r"))
            .contains { normalize($0) == target }
    }
}
