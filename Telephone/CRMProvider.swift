//
//  CRMProvider.swift
//  Telephone
//

import Foundation

struct CRMReferenceKey: Hashable, Sendable {
    let value: String
    let programs: [String]
}

struct CRMCustomerProfile: Sendable {
    let company: String
    let keys: [CRMReferenceKey]
    let emails: [String]

    var hasContent: Bool {
        !company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !keys.isEmpty
            || !emails.isEmpty
    }
}

protocol CRMProvider: Sendable {
    func customer(
        for address: CustomerPartyAddress
    ) async -> CRMCustomerProfile?
}

struct DisabledCRMProvider: CRMProvider {
    func customer(
        for address: CustomerPartyAddress
    ) async -> CRMCustomerProfile? {
        nil
    }
}
