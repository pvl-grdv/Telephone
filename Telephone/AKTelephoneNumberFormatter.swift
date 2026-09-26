//
//  AKTelephoneNumberFormatter.swift
//  Telephone
//
//  Swift implementation of Telephone's phone-number formatter.
//

import Foundation

public final class AKTelephoneNumberFormatter: Formatter {
    public var splitsLastFourDigits = false

    public override func string(for obj: Any?) -> String? {
        guard let value = obj as? String else {
            return nil
        }

        if isPlainDigitNumber(value), (6...15).contains(value.count) {
            return formatPlainNumber(
                value,
                splitLastFour: splitsLastFourDigits
            )
        }

        if isNorthAmericanInternationalNumber(value) {
            return formatNorthAmericanInternationalNumber(
                value,
                splitLastFour: splitsLastFourDigits
            )
        }

        return value
    }

    public override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        guard let number = extractedTelephoneNumber(from: string) else {
            error?.pointee =
                "Couldn't convert \"\(string)\" to telephone number" as NSString
            return false
        }

        obj?.pointee = number as NSString
        return true
    }

    public func telephoneNumber(from string: String) -> String {
        extractedTelephoneNumber(from: string) ?? ""
    }
}

private func isPlainDigitNumber(_ value: String) -> Bool {
    !value.isEmpty && value.allSatisfy(isASCIIDigit)
}

private func isNorthAmericanInternationalNumber(_ value: String) -> Bool {
    guard value.count == 12, value.first == "+" else {
        return false
    }

    let characters = Array(value)
    guard characters[1] == "1" || characters[1] == "7" else {
        return false
    }

    return characters.dropFirst(2).allSatisfy(isASCIIDigit)
}

private func isASCIIDigit(_ character: Character) -> Bool {
    character >= "0" && character <= "9"
}

private func formatPlainNumber(
    _ value: String,
    splitLastFour: Bool
) -> String {
    let length = value.count
    let groups: [Int]

    switch (length, splitLastFour) {
    case (6, true):
        groups = [2, 2, 2]
    case (6, false):
        groups = [3, 3]
    case (7, true):
        groups = [3, 2, 2]
    case (7, false):
        groups = [3, 4]
    case (8...10, true):
        groups = [length - 7, 3, 2, 2]
    case (8...10, false):
        groups = [length - 7, 3, 4]
    case (11...15, true):
        groups = [length - 10, 3, 3, 2, 2]
    case (11...15, false):
        groups = [length - 10, 3, 3, 4]
    default:
        return value
    }

    return split(value, groupSizes: groups).joined(separator: "-")
}

private func formatNorthAmericanInternationalNumber(
    _ value: String,
    splitLastFour: Bool
) -> String {
    let characters = Array(value)
    let country = String(characters[0...1])
    let area = String(characters[2...4])
    let exchange = String(characters[5...7])

    if splitLastFour {
        let first = String(characters[8...9])
        let second = String(characters[10...11])
        return "\(country) (\(area)) \(exchange)-\(first)-\(second)"
    }

    let subscriber = String(characters[8...11])
    return "\(country) (\(area)) \(exchange)-\(subscriber)"
}

private func split(
    _ value: String,
    groupSizes: [Int]
) -> [String] {
    let characters = Array(value)
    var start = 0

    return groupSizes.map { size in
        let end = start + size
        defer { start = end }
        return String(characters[start..<end])
    }
}

private func extractedTelephoneNumber(from string: String) -> String? {
    let startsWithPlus = string.hasPrefix("+")
    let allowed = startsWithPlus
        ? Set("0123456789")
        : Set("0123456789*#")

    var result = startsWithPlus ? "+" : ""
    let characters = startsWithPlus ? string.dropFirst() : Substring(string)

    for character in characters where allowed.contains(character) {
        result.append(character)
    }

    return result.isEmpty ? nil : result
}
