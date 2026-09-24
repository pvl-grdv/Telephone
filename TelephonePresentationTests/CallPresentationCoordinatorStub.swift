//
//  CallPresentationCoordinatorStub.swift
//  TelephonePresentationTests
//

import Foundation

final class CallPresentationCoordinator {}

struct CustomerContextNote: Identifiable, Sendable {
    let id: Int64
    let body: String
    let updatedAt: Date
}


struct CRMCustomerProfile: Sendable {
    let company: String
    let keys: [String]
    let emails: [String]

    var hasContent: Bool {
        !company.isEmpty || !keys.isEmpty || !emails.isEmpty
    }
}
