import Testing

@MainActor
struct AccountSessionTests {
    @Test func firstRegistrationCannotDialUntilAccountContextIsEstablished() {
        let session = AccountSession()
        #expect(!session.canMakeCalls)
        session.transition(to: .connecting)
        #expect(!session.canMakeCalls)
        session.transition(to: .available)
        #expect(session.canMakeCalls)
    }

    @Test func reconnectPreservesReadinessButOfflineRemovesIt() {
        let session = AccountSession()
        session.transition(to: .connectionLost)
        #expect(session.canMakeCalls)
        session.transition(to: .connecting)
        #expect(session.canMakeCalls)
        session.transition(to: .offline)
        #expect(!session.canMakeCalls)
        session.transition(to: .connecting)
        #expect(!session.canMakeCalls)
    }

    @Test func registrationIntentDoesNotDependOnWindowLifetimeOrResetConnectionState() {
        let session = AccountSession()
        session.transition(to: .unavailable)
        session.accountUnavailable = true
        session.attemptingToRegister = true
        session.attemptingToUnregister = true
        session.shouldPresentRegistrationError = true
        session.resetRegistrationIntent()
        #expect(!session.attemptingToRegister)
        #expect(!session.attemptingToUnregister)
        #expect(!session.shouldPresentRegistrationError)
        #expect(session.accountUnavailable)
        #expect(session.state == .unavailable)
        #expect(session.canMakeCalls)
    }
}
