//
//  CallHistoryViewPresenter.swift
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
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

import Foundation
import UseCases

@MainActor
final class CallHistoryViewPresenter {
    private let showRecords: @MainActor ([PresentationCallHistoryRecord]) -> Void
    private let dateFormatter: DateFormatter
    private let durationFormatter: DateComponentsFormatter

    init(
        showRecords: @escaping @MainActor ([PresentationCallHistoryRecord]) -> Void,
        dateFormatter: DateFormatter,
        durationFormatter: DateComponentsFormatter
    ) {
        self.showRecords = showRecords
        self.dateFormatter = dateFormatter
        self.durationFormatter = durationFormatter
    }
}

nonisolated extension CallHistoryViewPresenter: ContactCallHistoryRecordGetAllUseCaseOutput {
    func update(records: [ContactCallHistoryRecord]) {
        let result = records.map(makeRecord)
        Task { @MainActor in
            showRecords(result)
        }
    }

    private func makeRecord(from record: ContactCallHistoryRecord) -> PresentationCallHistoryRecord {
        return PresentationCallHistoryRecord(
            identifier: record.origin.identifier,
            contact: PresentationContact(contact: record.contact),
            date: dateFormatter.string(from: record.origin.date),
            duration: durationFormatter.string(from: TimeInterval(record.origin.duration)) ?? "",
            isIncoming: record.origin.isIncoming,
            isMissed: record.origin.isMissed,
            startedAt: record.origin.date,
            callerNumber: record.origin.uri.user,
            durationSeconds: record.origin.duration
        )
    }
}
