//
//  CallHistoryViewEventTarget.swift
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

import UseCases

@MainActor
final class CallHistoryViewEventTarget {
    private let recordsGet: UseCase
    private let recordRemoveAll: UseCase
    private let removeRecord: (String) -> Void
    private let makeCall: (String) -> Void

    init(
        recordsGet: UseCase,
        recordRemoveAll: UseCase,
        removeRecord: @escaping (String) -> Void,
        makeCall: @escaping (String) -> Void
    ) {
        self.recordsGet = recordsGet
        self.recordRemoveAll = recordRemoveAll
        self.removeRecord = removeRecord
        self.makeCall = makeCall
    }

    func shouldReloadData() {
        recordsGet.execute()
    }

    func shouldRemoveAllRecords() {
        recordRemoveAll.execute()
    }

    func didPickRecord(withIdentifier identifier: String) {
        makeCall(identifier)
    }

    func shouldRemoveRecord(withIdentifier identifier: String) {
        removeRecord(identifier)
    }
}

nonisolated extension CallHistoryViewEventTarget: CallHistoryEventTarget {
    func didUpdate(_ history: CallHistory) {
        Task { @MainActor in
            recordsGet.execute()
        }
    }
}

nonisolated extension CallHistoryViewEventTarget: DayChangeEventTarget {
    func dayDidChange() {
        Task { @MainActor in
            recordsGet.execute()
        }
    }
}
