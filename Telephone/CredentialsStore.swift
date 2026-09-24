//
//  CredentialsStore.swift
//  Telephone
//

import Foundation

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

    func deletePassword(
        service: String,
        account: String
    ) -> Bool {
        AKKeychain.removeItem(
            forService: service,
            account: account
        )
    }
}
