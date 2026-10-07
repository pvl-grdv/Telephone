import Foundation
import Observation

enum AccountConnectionState: Equatable {
    case offline
    case connecting
    case available
    case unavailable
    case connectionLost
}

/// Owned by AccountController; windows observe state, never own SIP intent.
@MainActor
@Observable
final class AccountSession {
    private(set) var state: AccountConnectionState = .offline
    private(set) var canMakeCalls = false
    var attemptingToRegister = false
    var attemptingToUnregister = false
    var shouldPresentRegistrationError = false
    var accountUnavailable = false

    func transition(to state: AccountConnectionState) {
        self.state = state
        switch state {
        case .offline:
            canMakeCalls = false
        case .available, .unavailable, .connectionLost:
            canMakeCalls = true
        case .connecting:
            // Reconnect retains readiness; first registration has no dialing
            // context until its result arrives.
            break
        }
    }

    func resetRegistrationIntent() {
        attemptingToRegister = false
        attemptingToUnregister = false
        shouldPresentRegistrationError = false
    }
}
