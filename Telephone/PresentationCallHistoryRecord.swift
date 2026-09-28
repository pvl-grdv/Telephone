//
//  PresentationCallHistoryRecord.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import Foundation

struct PresentationCallHistoryRecord: Identifiable, Hashable {
    let identifier: String
    let contact: PresentationContact
    let date: String
    let duration: String
    let isIncoming: Bool
    let isMissed: Bool

    var id: String { identifier }

    var name: String {
        contact.title.isEmpty ? date : "\(contact.title), \(date)"
    }

    func matchesSearch(_ query: String) -> Bool {
        let haystacks = [
            contact.title,
            contact.tooltip,
            contact.label,
            contact.address,
            date,
            duration,
        ]

        if haystacks.contains(where: {
            $0.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }) {
            return true
        }

        guard !query.contains(where: \.isLetter) else { return false }
        let queryDigits = query.filter(\.isNumber)
        guard !queryDigits.isEmpty else { return false }

        return contact.address.filter(\.isNumber).contains(queryDigits)
    }
}
