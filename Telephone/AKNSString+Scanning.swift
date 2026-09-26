//
//  AKNSString+Scanning.swift
//  Telephone
//
//  Small Swift string scanning helpers.
//

import Foundation

extension String {
    var ak_hasLetters: Bool {
        range(
            of: "[A-Za-z]",
            options: .regularExpression
        ) != nil
    }
}

extension NSString {
    var ak_hasLetters: Bool {
        (self as String).ak_hasLetters
    }
}
