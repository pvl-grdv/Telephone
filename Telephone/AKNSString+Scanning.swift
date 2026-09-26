//
//  AKNSString+Scanning.swift
//  Telephone
//

import Foundation

@objc(AKStringScanningAdditions) @implementation
extension NSString {
    var ak_hasLetters: Bool {
        (self as String).range(
            of: "[A-Za-z]",
            options: .regularExpression
        ) != nil
    }
}
