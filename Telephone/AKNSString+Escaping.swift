//
//  AKNSString+Escaping.swift
//  Telephone
//
//  Small Swift string escaping helpers.
//

import Foundation

extension String {
    func ak_escapeFirstCharacter(from string: String) -> String {
        guard let character = string.first else {
            return self
        }

        let value = String(character)
        return replacingOccurrences(
            of: value,
            with: "\\" + value
        )
    }

    func ak_escapeQuotes() -> String {
        ak_escapeFirstCharacter(from: "\"")
    }

    func ak_escapeParentheses() -> String {
        replacingOccurrences(of: ")", with: "\\)")
            .replacingOccurrences(of: "(", with: "\\(")
    }
}

extension NSString {
    var swiftString: String { self as String }

    func ak_escapeFirstCharacter(from string: String) -> String {
        swiftString.ak_escapeFirstCharacter(from: string)
    }

    func ak_escapeQuotes() -> String {
        swiftString.ak_escapeQuotes()
    }

    func ak_escapeParentheses() -> String {
        swiftString.ak_escapeParentheses()
    }
}
