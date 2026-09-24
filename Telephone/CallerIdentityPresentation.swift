//
//  CallerIdentityPresentation.swift
//  Telephone
//

import Foundation

@objcMembers
final class CallerIdentityPresentation: NSObject {
    let primary: String
    let detail: String

    init(primary: String, detail: String) {
        self.primary = primary
        self.detail = detail
    }

    @objc(
        makeWithSIPDisplayName:callSource:contactName:organization:label:
    )
    static func make(
        sipDisplayName: String,
        callSource: String,
        contactName: String,
        organization: String,
        label: String
    ) -> CallerIdentityPresentation {
        let cleanSource = clean(callSource)
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
        let left = clean(lhs)
        let right = clean(rhs)

        if left.caseInsensitiveCompare(right) == .orderedSame {
            return true
        }

        let leftDigits = left.filter(\.isNumber)
        let rightDigits = right.filter(\.isNumber)

        return leftDigits.count >= 7
            && leftDigits == rightDigits
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
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
