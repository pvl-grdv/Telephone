//
//  CallCustomerSummaryIdentity.swift
//  Telephone
//

import Foundation

/// Do not repeat an identity already visible above the compact CRM summary.
/// Whitespace/case and phone formatting are equivalent; distinct company names
/// remain distinct even when they happen to contain the same numeric code.
enum CallCustomerSummaryIdentity {
    static func distinctCompany(_ company: String, displayedName: String, identityDetail: String) -> String? {
        let company = clean(company)
        guard !company.isEmpty else { return nil }
        let visible = [displayedName] + identityDetail.components(separatedBy: " · ")
        return visible.contains { equivalent(company, clean($0)) } ? nil : company
    }

    private static func equivalent(_ lhs: String, _ rhs: String) -> Bool {
        if let phone = CRMPhoneNumber.normalize(lhs), let other = CRMPhoneNumber.normalize(rhs) {
            return phone == other
        }
        // sameIdentityValue also compares digit-only projections. That fallback
        // is deliberately avoided for organization names containing numbers.
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private static func clean(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
