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
import UseCases

struct PresentationCallHistoryRecord: Identifiable, Hashable {
    let identifier: String
    let contact: PresentationContact
    let date: String
    let duration: String
    let isIncoming: Bool
    let isMissed: Bool
    var startedAt: Date? = nil
    var callerNumber: String? = nil
    // Connected duration from SIP, independent of localized UI text.
    var durationSeconds: Int? = nil

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

extension PresentationCallHistoryRecord {
    init(
        record: ContactCallHistoryRecord,
        dateFormatter: DateFormatter,
        durationFormatter: DateComponentsFormatter
    ) {
        let call = record.origin
        self.init(
            identifier: call.identifier,
            contact: PresentationContact(contact: record.contact),
            date: dateFormatter.string(from: call.date),
            duration: durationFormatter.string(from: TimeInterval(call.duration)) ?? "",
            isIncoming: call.isIncoming,
            isMissed: call.isMissed,
            startedAt: call.date,
            callerNumber: call.uri.user,
            durationSeconds: call.duration
        )
    }
}
