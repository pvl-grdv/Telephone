//
//  CallHistoryCallEventTarget.swift
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

public final class CallHistoryCallEventTarget: Sendable {
    private let histories: CallHistories

    public init(histories: CallHistories) {
        self.histories = histories
    }
}

extension CallHistoryCallEventTarget: CallEventTarget {
    public func didDisconnect(_ call: Call) {
        Task {
            CallHistoryRecordAddUseCase(
                history: await histories.history(withUUID: call.account.uuid),
                record: CallHistoryRecord(call: call),
                domain: call.account.domain
            ).execute()
        }
    }

    public func didMake(_ call: Call) {}
    public func didReceive(_ call: Call) {}
    public func isConnecting(_ call: Call) {}
}
