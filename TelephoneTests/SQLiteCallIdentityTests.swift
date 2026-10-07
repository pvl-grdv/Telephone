import Foundation
import Testing
import UseCases

@CallHistoryActor
struct SQLiteCallIdentityTests {
    @Test func persistedIdentityRoundTripsAndRemovesExactCall() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite3")
        let history = SQLiteCallHistory(databaseURL: url, accountUUID: "account-a")
        let sameAddress = URI(user: "+70005550101", host: "", displayName: "Example")
        let first = CallHistoryRecord(uri: sameAddress, date: Date(timeIntervalSinceReferenceDate: 42),
            duration: 12, isIncoming: true, isMissed: false, identifier: "first-uuid")
        let second = CallHistoryRecord(uri: sameAddress, date: first.date, duration: 12,
            isIncoming: true, isMissed: false, identifier: "second-uuid")
        history.add(first)
        history.add(second)
        let reopened = SQLiteCallHistory(databaseURL: url, accountUUID: "account-a")
        #expect(reopened.allRecords.map { $0.identifier } == ["first-uuid", "second-uuid"])
        reopened.remove(reopened.allRecords[0])
        #expect(reopened.allRecords.map { $0.identifier } == ["second-uuid"])
        let other = SQLiteCallHistory(databaseURL: url, accountUUID: "account-b")
        other.add(first)
        #expect(other.allRecords.map { $0.identifier } == ["first-uuid"])
        #expect(reopened.allRecords.map { $0.identifier } == ["second-uuid"])
    }

    @Test func legacyDerivedIdentityRemainsUnchangedWhenRead() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite3")
        let history = SQLiteCallHistory(databaseURL: url, accountUUID: "legacy")
        let legacy = CallHistoryRecord(uri: URI(user: "101", host: "account.invalid", displayName: ""),
            date: Date(timeIntervalSinceReferenceDate: 15), duration: 0, isIncoming: true, isMissed: true)
        history.add(legacy)
        #expect(history.allRecords.first?.identifier == legacy.identifier)
    }
}
