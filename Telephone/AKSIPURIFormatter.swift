//
//  AKSIPURIFormatter.swift
//  Telephone
//
//  Swift implementation of Telephone's SIP URI formatter.
//

import Foundation

@objc @implementation
extension AKSIPURIFormatter {
    public var formatsTelephoneNumbers = false
    public var telephoneNumberFormatterSplitsLastFourDigits = false

    public override func string(for obj: Any?) -> String? {
        guard let uri = obj as? AKSIPURI else {
            return nil
        }

        if !uri.displayName.isEmpty {
            return uri.displayName
        }

        guard !uri.user.isEmpty else {
            return uri.host
        }

        if isTelephoneNumber(uri.user) {
            guard formatsTelephoneNumbers else {
                return uri.user
            }

            let formatter = AKTelephoneNumberFormatter()
            formatter.splitsLastFourDigits =
                telephoneNumberFormatterSplitsLastFourDigits
            return formatter.string(for: uri.user)
        }

        return uri.sipAddress
    }

    public override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        obj?.pointee = parsedDestination(from: string)
        return true
    }

    @objc(SIPURIFromString:)
    public func sipURI(from string: String) -> AKSIPURI {
        parsedDestination(from: string)
    }
}

private func isTelephoneNumber(_ value: String) -> Bool {
    let digits = value.first == "+"
        ? value.dropFirst()
        : Substring(value)

    return !digits.isEmpty
        && digits.allSatisfy { $0 >= "0" && $0 <= "9" }
}

private func parsedDestination(from input: String) -> AKSIPURI {
    if let uri = AKSIPURI(string: input) {
        return uri
    }

    if
        input.hasSuffix(")"),
        let delimiter = input.range(of: " (", options: .backwards),
        delimiter.lowerBound != input.startIndex
    {
        let destination = String(input[..<delimiter.lowerBound])
        let nameStart = delimiter.upperBound
        let nameEnd = input.index(before: input.endIndex)
        let name = String(input[nameStart..<nameEnd])

        return makeDestination(
            destination,
            displayName: name
        )
    }

    if
        input.hasSuffix(">"),
        let delimiter = input.range(of: " <", options: .backwards),
        delimiter.lowerBound != input.startIndex
    {
        let rawName = input[..<delimiter.lowerBound]
        let name = rawName.trimmingCharacters(
            in: CharacterSet.whitespaces.union(
                CharacterSet(charactersIn: "\"")
            )
        )

        let destinationStart = delimiter.upperBound
        let destinationEnd = input.index(before: input.endIndex)
        let destination = String(
            input[destinationStart..<destinationEnd]
        )

        return makeDestination(
            destination,
            displayName: name
        )
    }

    return makeDestination(input, displayName: "")
}

private func makeDestination(
    _ destination: String,
    displayName: String
) -> AKSIPURI {
    guard let at = destination.lastIndex(of: "@") else {
        return AKSIPURI(
            user: destination,
            host: "",
            displayName: displayName
        )
    }

    return AKSIPURI(
        user: String(destination[..<at]),
        host: String(destination[destination.index(after: at)...]),
        displayName: displayName
    )
}
