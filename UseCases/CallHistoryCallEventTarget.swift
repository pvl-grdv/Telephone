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

import Synchronization

public final class CallHistoryCallEventTarget: Sendable {
    private let histories: CallHistories
    private let pending = Mutex<PendingWrites>(PendingWrites())

    private struct PendingWrites {
        var generation: UInt64 = 0
        var tail: Task<Void, Never>?
    }

    /// Drain after the SIP producer has finalized its remaining calls.
    public func drain() async {
        while true {
            let snapshot = pending.withLock { ($0.generation, $0.tail) }
            await snapshot.1?.value
            let finished = pending.withLock { state in
                guard state.generation == snapshot.0 else { return false }
                state.tail = nil
                return true
            }
            if finished { return }
        }
    }

    public init(histories: CallHistories) {
        self.histories = histories
    }
}

extension CallHistoryCallEventTarget: CallEventTarget {
    public func didDisconnect(_ call: Call) {
        // Capture mutable SIP/account objects before the first suspension.
        let accountUUID = call.account.uuid
        let domain = call.account.domain
        let record = CallHistoryRecord(call: call)
        let histories = histories
        pending.withLock { state in
            let previous = state.tail
            state.generation &+= 1
            state.tail = Task {
                await previous?.value
                let history = await histories.history(withUUID: accountUUID)
                await CallHistoryRecordAddUseCase(
                    history: history,
                    record: record,
                    domain: domain
                ).executeAndWait()
            }
        }
    }

    public func didMake(_ call: Call) {}
    public func didReceive(_ call: Call) {}
    public func isConnecting(_ call: Call) {}
    public func didConnect(_ call: Call) {}
}
