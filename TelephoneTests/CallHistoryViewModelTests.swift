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
    private func record(id: String = "local-call", incoming: Bool = true, missed: Bool = true) -> PresentationCallHistoryRecord {
        PresentationCallHistoryRecord(identifier: id,
            contact: PresentationContact(title: "Synthetic Contact", tooltip: "", label: "", address: "+74959999999"),
            date: "Today", duration: "00:00", isIncoming: incoming, isMissed: missed,
            startedAt: Date(timeIntervalSince1970: 1_791_968_400), callerNumber: "84951234567")
    }
    @Test func visibleLocallyMissedIncomingCallsUseRawCallerAndKeepLocalMissedFlag() async throws {
        let provider = HistoryAnswerProvider()
        let model = CallHistoryViewModel(gatewaySettings: try await settings(), answerProvider: provider)
        let call = record()
        model.show([call, record(id: "outgoing", incoming: false), record(id: "accepted", missed: false)])
        for id in ["local-call", "outgoing", "accepted"] { model.setAnswerRecordVisible(id, visible: true) }
        #expect(model.answerContext.calls.count == 1)
        #expect(model.answerContext.calls.first?.phoneNumber == "+74951234567")
        await model.refreshCallAnswers()
        #expect(model.callAnswers[call.id]?.answeredBy?.displayName == "Synthetic Employee")
        #expect(model.allRecords.first?.isMissed == true)
        model.filter = .missed
        #expect(model.records.contains(where: { $0.id == call.id }))
        model.setAnswerRecordVisible(call.id, visible: false)
        #expect(model.answerContext.calls.isEmpty)
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
    @Test(arguments: ["delete", "disable", "replace"])
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
        } else {
            model.selection = "local-call"; _ = model.requestDeleteSelected()
            model.commitPendingDeletion(deleteRecord: { _ in }, deleteAll: {})
        }
        await provider.release(); await task.value
        #expect(model.callAnswers.isEmpty)
    }
}
private actor HistoryAnswerTokenStore: CRMGatewayTokenStoring {
    func token(for origin: String) -> String { "synthetic-token" }
    func save(_ token: String, for origin: String) -> Bool { true }
    func remove(for origin: String) -> Bool { true }
}
private actor HistoryAnswerProvider: CRMCallAnswerProvider {
    private var shouldFail = false
    private let held: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    init(held: Bool = false) { self.held = held }
    func fail() { shouldFail = true }
    func release() { continuation?.resume(); continuation = nil }
    func incomingCallAnswers(calls: [CRMIncomingCallRequest], configuration: CRMGatewayConfiguration) async throws -> [CRMIncomingCallAnswer] {
        if held { await withCheckedContinuation { continuation = $0 } }
        if shouldFail { throw CRMGatewayError.unavailable }
        return calls.map { call in
            CRMIncomingCallAnswer(id: call.id, phoneNumber: call.phoneNumber, startedAt: call.startedAt,
                status: .answered, reason: nil,
                answeredBy: .init(displayName: "Synthetic Employee", source: "ats"),
                match: .init(method: "phone-and-time", confidence: "correlated", startedAt: call.startedAt))
        }
    }
}
