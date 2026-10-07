import Foundation
import Synchronization
import Testing
import UseCases

@MainActor
struct SIPCallEventSequenceTests {
    @Test func creationAndTerminalBeforeActorRunsKeepMissedCall() async {
        let sequence = SIPCallEventSequence()
        let account = EventAccount()
        let completed = Mutex<[CallHistoryRecord]>([])
        sequence.enqueueCall(identifier: 7, account: account, incoming: true) { token in
            token.call.withLock { $0 = EventCall(token: token) }
        }
        sequence.enqueueCall(identifier: 7, account: account, endsCall: true) { token in
            guard let call = token.call.withLock({ $0 }) else {
                Issue.record("Queued incoming call was lost")
                return
            }
            completed.withLock { $0.append(CallHistoryRecord(call: call)) }
        }
        await sequence.drain()
        let records = completed.withLock { $0 }
        #expect(records.count == 1)
        #expect(records.first?.isIncoming == true)
        #expect(records.first?.isMissed == true)
    }

    @Test func queuedTerminalTargetsOldIncarnationAfterIdentifierReuse() async {
        let sequence = SIPCallEventSequence()
        let account = EventAccount()
        let old = sequence.capture(identifier: 7, account: account, incoming: true)!
        let oldCall = EventCall(token: old)
        old.call.withLock { $0 = oldCall }
        let capturedTerminal = sequence.capture(identifier: 7, account: account, endsCall: true)!
        let replacement = sequence.capture(identifier: 7, account: account, incoming: true)!
        let newCall = EventCall(token: replacement)
        replacement.call.withLock { $0 = newCall }
        sequence.enqueue {
            #expect(capturedTerminal.call.withLock { $0 } === oldCall)
            #expect(replacement.call.withLock { $0 } === newCall)
            #expect(capturedTerminal.historyIdentifier != replacement.historyIdentifier)
        }
        await sequence.drain()
    }

    @Test func callbacksFinishInSubmissionOrder() async {
        let sequence = SIPCallEventSequence()
        let order = Mutex<[Int]>([])
        for i in 0..<50 { sequence.enqueue { order.withLock { $0.append(i) } } }
        await sequence.drain()
        #expect(order.withLock { $0 } == Array(0..<50))
    }

    @Test func capturedTerminalSurvivesRegistryRemoval() async {
        let sequence = SIPCallEventSequence()
        let account = EventAccount()
        let token = sequence.capture(identifier: 7, account: account, incoming: true)!
        let call = EventCall(token: token)
        token.call.withLock { $0 = call }
        let captured = sequence.capture(identifier: 7, account: account, endsCall: true)!
        sequence.resetAfterStopping()
        let records = Mutex<[CallHistoryRecord]>([])
        sequence.enqueue {
            guard let retained = captured.call.withLock({ $0 }) else {
                Issue.record("Removed registry discarded the terminal call")
                return
            }
            records.withLock { $0.append(CallHistoryRecord(call: retained)) }
        }
        await sequence.drain()
        #expect(records.withLock { $0.first?.identifier } == call.historyIdentifier)
        #expect(records.withLock { $0.first?.duration } == 24)
    }
}

private final class EventAccount: Account {
    let uuid = "synthetic-account"
    let domain = "account.invalid"
}

private final class EventCall: NSObject, Call, CallHistoryIdentified {
    let account: any Account
    let historyIdentifier: String
    let remote = URI(user: "101", host: "account.invalid", displayName: "")
    let date = Date(timeIntervalSinceReferenceDate: 12)
    let duration = 24
    let isIncoming = true
    let isMissed = true

    init(token: SIPCallIncarnation) {
        account = token.account
        historyIdentifier = token.historyIdentifier
    }
}
