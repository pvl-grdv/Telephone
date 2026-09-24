//
//  CredentialsStoring.swift
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
    func deletePassword(
        service: String,
        account: String
    ) async -> Bool
}
