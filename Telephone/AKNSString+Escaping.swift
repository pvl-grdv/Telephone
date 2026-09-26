//
//  AKNSString+Escaping.swift
//  Telephone
//

import Foundation

@objc(AKStringEscapingAdditions) @implementation
extension NSString {
    @objc(ak_escapeFirstCharacterFromString:)
    func ak_escapeFirstCharacter(from string: String) -> String {
        guard let character = string.first else {
            return self as String
        }
        let value = String(character)
        return (self as String).replacingOccurrences(
            of: value,
            with: "\\" + value
        )
    }

    func ak_escapeQuotes() -> String {
        ak_escapeFirstCharacter(from: "\"")
    }

    func ak_escapeParentheses() -> String {
        let closing = (self as String).replacingOccurrences(
            of: ")",
            with: "\\)"
        )
        return closing.replacingOccurrences(
            of: "(",
            with: "\\("
        )
    }
}
