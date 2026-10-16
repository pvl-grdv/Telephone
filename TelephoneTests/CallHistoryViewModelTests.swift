//
//  CallHistoryViewModelTests.swift
//  TelephoneTests
//

import Testing
import Foundation

@MainActor
struct CallHistoryViewModelTests {
    @Test
    func filtersVisibleRecordsByCallKind() {
        let incoming = record(
            id: "incoming",
            address: "111",
            incoming: true,
            missed: false
        )
        let missed = record(
            id: "missed",
            address: "222",
            incoming: true,
            missed: true
        )
        let outgoing = record(
            id: "outgoing",
            address: "333",
            incoming: false,
            missed: false
        )
        let model = CallHistoryViewModel()
        model.show([incoming, missed, outgoing])

        model.filter = .missed
        #expect(model.records.map(\.identifier) == ["missed"])

        model.filter = .incoming
        #expect(
            model.records.map(\.identifier)
                == ["incoming", "missed"]
        )

        model.filter = .outgoing
        #expect(model.records.map(\.identifier) == ["outgoing"])
    }

    @Test
    func searchUpdatesCachedVisibleRecordsAndNormalizesSelection() {
        let alice = record(
            id: "alice",
            title: "Alice",
            address: "+1 202 555 0100",
            incoming: true,
            missed: false
        )
        let bob = record(
            id: "bob",
            title: "Bob",
            address: "+1 202 555 0199",
            incoming: false,
            missed: false
        )

        let model = CallHistoryViewModel()
        model.show([alice, bob])
        model.selection = "bob"

        model.query = "0100"

        #expect(model.records.map(\.identifier) == ["alice"])
        #expect(model.selection == nil)
    }

    @Test
    func combinesCallKindAndTextSearchWithoutLosingRecordOrder() {
        let missedMatch = record(
            id: "missed-match", title: "Alpha", address: "111",
            incoming: true, missed: true
        )
        let outgoingMatch = record(
            id: "outgoing-match", title: "Alpha", address: "222",
            incoming: false, missed: false
        )
        let missedOther = record(
            id: "missed-other", title: "Beta", address: "333",
            incoming: true, missed: true
        )
        let model = CallHistoryViewModel()
        model.show([missedMatch, outgoingMatch, missedOther])
        model.selection = outgoingMatch.id

        model.filter = .missed
        model.query = " ALPHA "
        #expect(model.records.map(\.id) == ["missed-match"])
        #expect(model.selection == nil)

        model.query = "  "
        #expect(model.records.map(\.id) == ["missed-match", "missed-other"])
        model.filter = .all
        #expect(model.records.map(\.id) == ["missed-match", "outgoing-match", "missed-other"])
    }

    @Test
    func deletingVisibleRecordUpdatesSourceAndVisibleCaches() {
        let first = record(
            id: "first",
            address: "111",
            incoming: true,
            missed: false
        )
        let second = record(
            id: "second",
            address: "222",
            incoming: false,
            missed: false
        )

        let model = CallHistoryViewModel()
        model.show([first, second])
        model.selection = "first"
        #expect(model.requestDeleteSelected())

        var deletedIdentifier: String?
        model.commitPendingDeletion(
            deleteRecord: { deletedIdentifier = $0 },
            deleteAll: {}
        )

        #expect(deletedIdentifier == "first")
        #expect(model.allRecords.map(\.identifier) == ["second"])
        #expect(model.records.map(\.identifier) == ["second"])
        #expect(model.selection == nil)
    }

    @Test
    func deletingAllHistoryClearsRecordsAndSelection() {
        let first = record(id: "first", address: "111", incoming: true, missed: false)
        let second = record(id: "second", address: "222", incoming: false, missed: false)
        let model = CallHistoryViewModel()
        model.show([first, second])
        model.selection = first.identifier
        #expect(model.requestDeleteAll())

        var deleteAllCount = 0
        model.commitPendingDeletion(
            deleteRecord: { _ in Issue.record("Expected delete all, not a single record") },
            deleteAll: { deleteAllCount += 1 }
        )

        #expect(deleteAllCount == 1)
        #expect(model.allRecords.isEmpty)
        #expect(model.records.isEmpty)
        #expect(model.selection == nil)
        #expect(model.pendingDeletion == nil)
    }

    private func record(
        id: String,
        title: String = "",
        address: String,
        incoming: Bool,
        missed: Bool
    ) -> PresentationCallHistoryRecord {
        PresentationCallHistoryRecord(
            identifier: id,
            contact: PresentationContact(
                title: title,
                tooltip: address,
                label: "",
                address: address
            ),
            date: "Today",
            duration: "00:10",
            isIncoming: incoming,
            isMissed: missed
        )
    }
}

@MainActor
struct CallHistoryAnswerTests {
    private func settings() async throws -> CRMGatewaySettings {
        let defaults = UserDefaults(suiteName: "CallHistoryAnswerTests.\(UUID().uuidString)")!
        let settings = CRMGatewaySettings(defaults: defaults, tokenStore: HistoryAnswerTokenStore())
        try await settings.save(enabled: true, origin: "https://gateway.example.invalid", newToken: "synthetic-token")
        return settings
    }
    private func record(
        id: String = "local-call", incoming: Bool = true,
        missed: Bool = true, durationSeconds: Int = 0
    ) -> PresentationCallHistoryRecord {
        PresentationCallHistoryRecord(identifier: id,
            contact: PresentationContact(title: "Synthetic Contact", tooltip: "", label: "", address: "+74959999999"),
            date: "Today", duration: "00:00", isIncoming: incoming, isMissed: missed,
            startedAt: Date(timeIntervalSince1970: 1_791_968_400), callerNumber: "84951234567",
            durationSeconds: durationSeconds)
    }
    @Test func onlyVisibleIncomingCallsNotAnsweredHereUseATSAttribution() async throws {
        let provider = HistoryAnswerProvider()
        let model = CallHistoryViewModel(gatewaySettings: try await settings(), answerProvider: provider)
        let missed = record()
        let declined = record(id: "declined", missed: false, durationSeconds: 0)
        let accepted = record(id: "accepted", missed: false, durationSeconds: 25)
        model.show([missed, record(id: "outgoing", incoming: false), accepted, declined])
        for id in ["local-call", "outgoing", "accepted", "declined"] {
            model.setAnswerRecordVisible(id, visible: true)
        }
        #expect(Set(model.answerContext.calls.map(\.id)) == ["local-call", "declined"])
        #expect(model.answerContext.calls.first?.phoneNumber == "+74951234567")
        #expect(model.answerContext.calls.first?.startedAt == "2026-10-14T09:00:00.000Z")
        await model.refreshCallAnswers()
        #expect(model.callAnswers[missed.id]?.answeredBy?.displayName == "Synthetic Employee")
        #expect(model.callAnswers[declined.id]?.answeredBy?.displayName == "Synthetic Employee")
        #expect(model.callAnswers[accepted.id] == nil)
        #expect(await provider.requestCount == 1)
        #expect(model.allRecords.first?.isMissed == true)
        model.filter = .missed
        #expect(model.records.contains(where: { $0.id == missed.id }))
        model.setAnswerRecordVisible(missed.id, visible: false)
        #expect(model.answerContext.calls.isEmpty)
    }

    @Test func locallyAnsweredTransferredCallDoesNotReportATSTimeMismatch() async throws {
        let provider = HistoryAnswerProvider(status: .unknown)
        let model = CallHistoryViewModel(gatewaySettings: try await settings(), answerProvider: provider)
        // A transferred call's original ATS leg can begin before the SIP leg
        // answered on this Mac. The local positive duration is authoritative.
        let answeredHere = record(id: "transferred-to-me", missed: false, durationSeconds: 14 * 60 + 50)
        model.show([answeredHere])
        model.setAnswerRecordVisible(answeredHere.id, visible: true)

        #expect(!answeredHere.wasNotAnsweredHere)
        #expect(model.answerContext.calls.isEmpty)
        await model.refreshCallAnswers()
        #expect(await provider.requestCount == 0)
        #expect(model.callAnswers[answeredHere.id] == nil)
        #expect(model.records.first?.durationSeconds == 890)
    }
    @Test func aDeclinedZeroSecondCallWithoutMissedFlagCanShowWhoAnsweredElsewhere() async throws {
        let model = CallHistoryViewModel(gatewaySettings: try await settings(),
            answerProvider: HistoryAnswerProvider())
        let declined = record(id: "declined-by-me", incoming: true, missed: false, durationSeconds: 0)
        model.show([declined])
        model.setAnswerRecordVisible(declined.id, visible: true)

        #expect(model.answerContext.calls.map(\.id) == ["declined-by-me"])
        await model.refreshCallAnswers()
        #expect(model.callAnswers[declined.id]?.status == .answered)
        #expect(model.callAnswers[declined.id]?.answeredBy?.displayName == "Synthetic Employee")
        // ATS never overwrites locally observed SIP duration or missed status.
        #expect(model.allRecords.first?.durationSeconds == 0)
        #expect(model.allRecords.first?.isMissed == false)
    }

    @Test func failedReadRemovesPreviouslyDisplayedEmployeeInsteadOfClaimingNoAnswer() async throws {
        let provider = HistoryAnswerProvider()
        let model = CallHistoryViewModel(gatewaySettings: try await settings(), answerProvider: provider)
        model.show([record()]); model.setAnswerRecordVisible("local-call", visible: true)
        await model.refreshCallAnswers()
        #expect(model.callAnswers["local-call"] != nil)
        await provider.fail()
        await model.refreshCallAnswers()
        #expect(model.callAnswers.isEmpty)
        #expect(model.answerLookupFailed)
    }
    @Test func unsupportedGatewayIsDistinguishedFromANoMatchOutcome() async throws {
        let provider = HistoryAnswerProvider()
        await provider.fail(with: .callAnswersUnsupported)
        let model = CallHistoryViewModel(gatewaySettings: try await settings(), answerProvider: provider)
        model.show([record()]); model.setAnswerRecordVisible("local-call", visible: true)
        await model.refreshCallAnswers()
        #expect(model.answerLookupError == .callAnswersUnsupported)
        #expect(model.callAnswers.isEmpty)
    }

    @Test(arguments: ["delete", "disable", "replace", "hide", "cancel"])
    func lateAnswerCannotAttachAfterRecordOrSettingsChange(change: String) async throws {
        let provider = HistoryAnswerProvider(held: true)
        let settings = try await settings()
        let model = CallHistoryViewModel(gatewaySettings: settings, answerProvider: provider)
        model.show([record()]); model.setAnswerRecordVisible("local-call", visible: true)
        let task = Task { await model.refreshCallAnswers() }
        while !(await provider.waiting) { await Task.yield() }
        if change == "disable" {
            try await settings.save(enabled: false, origin: settings.origin, newToken: "")
        } else if change == "replace" {
            var replacement = record(); replacement.callerNumber = "+74951111111"
            model.show([replacement])
        } else if change == "hide" {
            model.setAnswerRecordVisible("local-call", visible: false)
        } else if change == "cancel" {
            task.cancel()
        } else {
            model.selection = "local-call"; _ = model.requestDeleteSelected()
            model.commitPendingDeletion(deleteRecord: { _ in }, deleteAll: {})
        }
        await provider.release(); await task.value
        #expect(model.callAnswers.isEmpty)
    }

    @Test func cancelledTokenReadDoesNotSendAnAnswerRequest() async throws {
        let defaults = UserDefaults(suiteName: "CallHistoryAnswerCancellation.\(UUID().uuidString)")!
        let tokenStore = HeldHistoryAnswerTokenStore()
        let settings = CRMGatewaySettings(defaults: defaults, tokenStore: tokenStore)
        try await settings.save(enabled: true, origin: "https://gateway.example.invalid", newToken: "synthetic-token")
        let provider = HistoryAnswerProvider()
        let model = CallHistoryViewModel(gatewaySettings: settings, answerProvider: provider)
        model.show([record()]); model.setAnswerRecordVisible("local-call", visible: true)
        let task = Task { await model.refreshCallAnswers() }
        while !(await tokenStore.waiting) { await Task.yield() }
        task.cancel()
        await tokenStore.release()
        await task.value
        #expect(await provider.requestCount == 0)
        #expect(model.callAnswers.isEmpty)
        #expect(!model.answerLookupFailed)
    }

    @Test(arguments: [CRMIncomingCallAnswer.Status.unanswered, .unknown])
    func unansweredOrUnknownCallsHaveNoAnsweringEmployee(status: CRMIncomingCallAnswer.Status) async throws {
        let model = CallHistoryViewModel(gatewaySettings: try await settings(),
            answerProvider: HistoryAnswerProvider(status: status))
        model.show([record()]); model.setAnswerRecordVisible("local-call", visible: true)
        await model.refreshCallAnswers()
        #expect(model.callAnswers["local-call"]?.status == status)
        #expect(model.callAnswers["local-call"]?.answeredBy == nil)
        #expect(!model.answerLookupFailed)
        #expect(model.allRecords.first?.isMissed == true)
    }
}
private actor HistoryAnswerTokenStore: CRMGatewayTokenStoring {
    func token(for origin: String) -> String { "synthetic-token" }
    func save(_ token: String, for origin: String) -> Bool { true }
    func remove(for origin: String) -> Bool { true }
}
private actor HistoryAnswerProvider: CRMCallAnswerProvider {
    private var failure: CRMGatewayError?
    private let held: Bool
    private let status: CRMIncomingCallAnswer.Status
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0
    var waiting: Bool { continuation != nil }
    init(held: Bool = false, status: CRMIncomingCallAnswer.Status = .answered) {
        self.held = held
        self.status = status
    }
    func fail(with error: CRMGatewayError = .unavailable) { failure = error }
    func release() { continuation?.resume(); continuation = nil }
    func incomingCallAnswers(calls: [CRMIncomingCallRequest], configuration: CRMGatewayConfiguration) async throws -> [CRMIncomingCallAnswer] {
        requestCount += 1
        if held { await withCheckedContinuation { continuation = $0 } }
        if let failure { throw failure }
        return calls.map { call in
            CRMIncomingCallAnswer(id: call.id, phoneNumber: call.phoneNumber, startedAt: call.startedAt,
                status: status, reason: status == .unknown ? "not-found" : nil,
                answeredBy: status == .answered ? .init(displayName: "Synthetic Employee", source: "ats") : nil,
                match: status == .unknown ? nil : .init(method: "phone-and-time", confidence: "correlated", startedAt: call.startedAt))
        }
    }
}

private actor HeldHistoryAnswerTokenStore: CRMGatewayTokenStoring {
    private var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    func token(for origin: String) async -> String {
        await withCheckedContinuation { continuation = $0 }
        return "synthetic-token"
    }
    func save(_ token: String, for origin: String) -> Bool { true }
    func remove(for origin: String) -> Bool { true }
    func release() { continuation?.resume(); continuation = nil }
}
