//
//  CallHistoryViewModelTests.swift
//  TelephoneTests
//

import Testing

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
