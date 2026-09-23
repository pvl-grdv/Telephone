//
//  CredentialsStore.swift
//  Telephone
//

import Foundation

protocol CredentialsStoring: Sendable {
    func password(service: String, account: String) async -> String
    func savePassword(
        _ password: String,
        service: String,
        account: String
    ) async -> Bool
}

actor CredentialsStore: CredentialsStoring {
    static let shared = CredentialsStore()

    func password(service: String, account: String) -> String {
        AKKeychain.password(
            forService: service,
            account: account
        )
    }

    func savePassword(
        _ password: String,
        service: String,
        account: String
    ) -> Bool {
        AKKeychain.addItem(
            withService: service,
            account: account,
            password: password
        )
    }
}
