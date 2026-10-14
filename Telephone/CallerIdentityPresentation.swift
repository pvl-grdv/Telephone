//
//  CallerIdentityPresentation.swift
//  Telephone
//

import Foundation

/// Display-only decoding of upstream HTML quote entities, never addresses or
/// write parameters. Deliberately keep &amp; encoded to avoid double-decoding.
enum DisplayNameText {
    private static let namedQuotes: [String: String] = [
        "quot": "\"", "apos": "'", "laquo": "«", "raquo": "»",
        "ldquo": "“", "rdquo": "”"
    ]
    private static let numericQuotes: [Int: String] = [
        34: "\"", 39: "'", 171: "«", 187: "»", 8220: "“", 8221: "”"
    ]

    static func normalized(_ source: String) -> String {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"&(?:quot|apos|laquo|raquo|ldquo|rdquo|#(?:x[0-9a-f]+|[0-9]+));"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return value
        }
        let matches = regex.matches(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value))
        guard !matches.isEmpty else { return value }
        var output = ""
        var cursor = value.startIndex
        for match in matches {
            guard let range = Range(match.range, in: value) else { continue }
            output += value[cursor..<range.lowerBound]
            let entity = String(value[range])
            let token = entity.dropFirst().dropLast().lowercased()
            let number: Int?
            if token.hasPrefix("#x") {
                number = Int(token.dropFirst(2), radix: 16)
            } else if token.hasPrefix("#") {
                number = Int(token.dropFirst())
            } else {
                number = nil
            }
            output += namedQuotes[token] ?? number.flatMap { numericQuotes[$0] } ?? entity
            cursor = range.upperBound
        }
        output += value[cursor...]
        return output
    }

    static func comparable(_ value: String) -> String {
        normalized(value).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func equivalent(_ lhs: String, _ rhs: String) -> Bool {
        let left = comparable(lhs)
        let right = comparable(rhs)
        if left.caseInsensitiveCompare(right) == .orderedSame { return true }
        if let phone = CRMPhoneNumber.normalize(left),
           let other = CRMPhoneNumber.normalize(right) {
            return phone == other
        }
        return false
    }
}

final class CallerIdentityPresentation {
    let primary: String
    let detail: String

    init(primary: String, detail: String) {
        self.primary = primary
        self.detail = detail
    }

    static func make(
        sipDisplayName: String,
        callSource: String,
        contactName: String,
        organization: String,
        label: String
    ) -> CallerIdentityPresentation {
        let cleanSource = callSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSIPName = clean(sipDisplayName)
        let cleanContactName = clean(contactName)
        let cleanOrganization = clean(organization)
        let cleanLabel = clean(label)

        let primary: String
        if !cleanContactName.isEmpty,
           !sameIdentityValue(cleanContactName, cleanSource) {
            primary = cleanContactName
        } else if !cleanOrganization.isEmpty,
                  !sameIdentityValue(cleanOrganization, cleanSource) {
            primary = cleanOrganization
        } else if !cleanSIPName.isEmpty,
                  !sameIdentityValue(cleanSIPName, cleanSource) {
            primary = cleanSIPName
        } else {
            primary = cleanSource
        }

        var details: [String] = []
        appendDistinct(
            cleanOrganization,
            excluding: [primary, cleanSource],
            to: &details
        )
        appendDistinct(
            cleanLabel,
            excluding: [primary],
            to: &details
        )
        appendDistinct(
            cleanSource,
            excluding: [primary],
            to: &details
        )

        return CallerIdentityPresentation(
            primary: primary,
            detail: details.joined(separator: " · ")
        )
    }

    static func promotingCompany(
        _ company: String,
        currentPrimary: String,
        currentDetail: String
    ) -> CallerIdentityPresentation {
        let cleanCompany = clean(company)
        guard !cleanCompany.isEmpty else {
            return CallerIdentityPresentation(
                primary: clean(currentPrimary),
                detail: clean(currentDetail)
            )
        }

        var details: [String] = []
        appendDistinct(
            clean(currentPrimary),
            excluding: [cleanCompany],
            to: &details
        )

        for value in currentDetail.components(separatedBy: " · ") {
            appendDistinct(
                clean(value),
                excluding: [cleanCompany],
                to: &details
            )
        }

        return CallerIdentityPresentation(
            primary: cleanCompany,
            detail: details.joined(separator: " · ")
        )
    }

    static func sameIdentityValue(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        DisplayNameText.equivalent(lhs, rhs)
    }

    private static func appendDistinct(
        _ value: String,
        excluding excluded: [String],
        to result: inout [String]
    ) {
        guard !value.isEmpty else { return }
        guard !excluded.contains(where: {
            sameIdentityValue($0, value)
        }) else {
            return
        }
        guard !result.contains(where: {
            sameIdentityValue($0, value)
        }) else {
            return
        }

        result.append(value)
    }

    private static func clean(_ value: String) -> String {
        DisplayNameText.normalized(value)
    }
}
