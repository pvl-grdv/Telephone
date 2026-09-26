//
//  CallHistoryViewEventTargetFactory.swift
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

@MainActor
final class CallHistoryViewEventTargetFactory {
    private let histories: CallHistories
    private let index: ContactMatchingIndex
    private let settings: ContactMatchingSettings
    private let dateFormatter: DateFormatter
    private let durationFormatter: DateComponentsFormatter
    private let dayChangeEventTargets: DayChangeEventTargets

    init(
        histories: CallHistories,
        index: ContactMatchingIndex,
        settings: ContactMatchingSettings,
        dateFormatter: DateFormatter,
        durationFormatter: DateComponentsFormatter,
        dayChangeEventTargets: DayChangeEventTargets
    ) {
        self.histories = histories
        self.index = index
        self.settings = settings
        self.dateFormatter = dateFormatter
        self.durationFormatter = durationFormatter
        self.dayChangeEventTargets = dayChangeEventTargets
    }

    func make(account: Account, view: CallHistoryView) async -> CallHistoryViewEventTarget {
        let history = await histories.history(withUUID: account.uuid)
        let factory = FallingBackMatchedContactFactory(
            matching: IndexedContactMatching(
                index: index,
                significantPhoneNumberLength: await settings.significantPhoneNumberLength,
                domain: account.domain
            )
        )
        let result = CallHistoryViewEventTarget(
            recordsGet: CallHistoryRecordGetAllUseCase(
                history: history,
                output: ContactCallHistoryRecordGetAllUseCase(
                    factory: factory,
                    output: CallHistoryViewPresenter(
                        view: view,
                        dateFormatter: dateFormatter,
                        durationFormatter: durationFormatter
                    )
                )
            ),
            recordRemoveAll: CallHistoryRecordRemoveAllUseCase(history: history),
            removeRecord: { identifier in
                CallHistoryRecordRemoveUseCase(identifier: identifier, history: history).execute()
            },
            makeCall: { identifier in
                CallHistoryRecordGetUseCase(
                    identifier: identifier,
                    history: history,
                    output: ContactCallHistoryRecordGetUseCase(
                        factory: factory,
                        output: CallHistoryCallMakeUseCase(account: account)
                    )
                ).execute()
            }
        )
        await history.updateTarget(WeakCallHistoryEventTarget(origin: result))
        dayChangeEventTargets.add(WeakDayChangeEventTarget(origin: result))
        return result
    }
}
