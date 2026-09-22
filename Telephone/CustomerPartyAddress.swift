//
//  CustomerPartyAddress.swift
//  Telephone
//
//  Stable local identity for phone, SIP, and email addresses.
//

import Foundation

struct CustomerPartyAddress: Equatable, Sendable {
    let kind: String
    let value: String
    let normalizedValue: String

    init(user: String, host: String) {
        let user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)

        let digits = user.filter(\.isNumber)
        let looksLikeSIPExtension =
            !host.isEmpty
            && !digits.isEmpty
            && digits.count <= 6
            && digits.count == user.filter({ !$0.isWhitespace }).count
        let looksLikeSIP =
            !host.isEmpty
            && (user.contains(where: \.isLetter) || looksLikeSIPExtension)

        if looksLikeSIP {
            kind = "sip"
            value = "\(user)@\(host)"
            normalizedValue = value.lowercased()
        } else {
            kind = "phone"
            value = user
            normalizedValue = digits.isEmpty ? user.lowercased() : digits
        }
    }

    init(email: String) {
        kind = "email"
        value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedValue = value.lowercased()
    }
}
