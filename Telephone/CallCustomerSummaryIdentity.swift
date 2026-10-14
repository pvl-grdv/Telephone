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
        let company = DisplayNameText.comparable(company)
        guard !company.isEmpty else { return nil }
        let visible = [displayedName] + identityDetail.components(separatedBy: " · ")
        return visible.contains { DisplayNameText.equivalent(company, $0) } ? nil : company
    }

}
