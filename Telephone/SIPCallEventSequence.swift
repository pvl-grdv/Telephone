import Foundation
import Synchronization
import UseCases

/// Captured at the C boundary, before a callback is queued on the main actor.
/// A recycled numeric PJSIP ID cannot change the call this token denotes.
final class SIPCallIncarnation: Sendable {
    let identifier: Int
    let historyIdentifier = UUID().uuidString
    let account: any Account
    let call = Mutex<(any Call)?>(nil)
    let latestDuration = Mutex<Int?>(nil)
    fileprivate let terminalQueued = Mutex<Bool>(false)

    init(identifier: Int, account: any Account) {
        self.identifier = identifier
        self.account = account
    }
}

final class SIPCallEventSequence: Sendable {
    static let shared = SIPCallEventSequence()
    private struct State {
        var incarnations: [Int: SIPCallIncarnation] = [:]
        var tail: Task<Void, Never>?
        var generation: UInt64 = 0
    }
    private let state = Mutex<State>(State())

    func capture(identifier: Int, account: (any Account)?, startsCall: Bool = false,
                 incoming: Bool = false, endsCall: Bool = false) -> SIPCallIncarnation? {
        state.withLock { state in
            capture(in: &state, identifier: identifier, account: account,
                    startsCall: startsCall, incoming: incoming, endsCall: endsCall)
        }
    }

    private func capture(in state: inout State, identifier: Int, account: (any Account)?,
                         startsCall: Bool, incoming: Bool, endsCall: Bool) -> SIPCallIncarnation? {
        var token = state.incarnations[identifier]
        let previousEnded = token?.terminalQueued.withLock { $0 } ?? false
        if incoming || token == nil || (startsCall && previousEnded) {
            guard let account else { return nil }
            token = SIPCallIncarnation(identifier: identifier, account: account)
            state.incarnations[identifier] = token
        }
        if endsCall { token?.terminalQueued.withLock { $0 = true } }
        return token
    }

    /// Reserve identity and delivery order under one lock, across C callback threads.
    func enqueueCall(identifier: Int, account: (any Account)?, startsCall: Bool = false,
                     incoming: Bool = false, endsCall: Bool = false, duration: Int? = nil,
                     action: @escaping @MainActor @Sendable (SIPCallIncarnation) -> Void) {
        state.withLock { state in
            guard let token = capture(in: &state, identifier: identifier, account: account,
                                      startsCall: startsCall, incoming: incoming, endsCall: endsCall) else { return }
            if let duration { token.latestDuration.withLock { $0 = duration } }
            append(to: &state) { action(token) }
        }
    }

    func enqueue(_ action: @escaping @MainActor @Sendable () -> Void) {
        state.withLock { append(to: &$0, action: action) }
    }

    private func append(to state: inout State, action: @escaping @MainActor @Sendable () -> Void) {
        let previous = state.tail
        state.generation &+= 1
        state.tail = Task {
            await previous?.value
            await action()
        }
    }

    func drain() async {
        while true {
            let snapshot = state.withLock { ($0.generation, $0.tail) }
            await snapshot.1?.value
            let done = state.withLock { state in
                guard state.generation == snapshot.0 else { return false }
                state.tail = nil
                return true
            }
            if done { return }
        }
    }

    func capturedDuration(identifier: Int, historyIdentifier: String) -> Int? {
        state.withLock { state in
            guard let token = state.incarnations[identifier], token.historyIdentifier == historyIdentifier else { return nil }
            return token.latestDuration.withLock { $0 }
        }
    }

    func resetAfterStopping() {
        state.withLock { $0.incarnations.removeAll() }
    }
}
