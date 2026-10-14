//
//  CallHistoryModel.swift
//  Telephone
//

import Foundation
import Observation

enum CallHistoryFilter: Int, CaseIterable, Hashable {
    case all
    case missed
    case incoming
    case outgoing

    var title: String {
        switch self {
        case .all:
            NSLocalizedString("All", comment: "All call history filter.")
        case .missed:
            NSLocalizedString("Missed", comment: "Missed call history filter.")
        case .incoming:
            NSLocalizedString("Incoming", comment: "Incoming call history filter.")
        case .outgoing:
            NSLocalizedString("Outgoing", comment: "Outgoing call history filter.")
        }
    }

    func matches(_ record: PresentationCallHistoryRecord) -> Bool {
        switch self {
        case .all:
            true
        case .missed:
            record.isMissed
        case .incoming:
            record.isIncoming
        case .outgoing:
            !record.isIncoming
        }
    }
}

enum CallHistoryDeletion {
    case record(PresentationCallHistoryRecord)
    case all

    var title: String {
        switch self {
        case .record(let record):
            String(
                format: NSLocalizedString(
                    "Are you sure you want to delete the record “%@”?",
                    comment: "Call history record removal alert."
                ),
                record.name
            )
        case .all:
            NSLocalizedString(
                "Are you sure you want to delete all records?",
                comment: "Call history all records removal alert."
            )
        }
    }
}

@MainActor
@Observable
final class CallHistoryViewModel {
    @ObservationIgnored private let gatewaySettings: CRMGatewaySettings?
    @ObservationIgnored private let answerProvider: any CRMCallAnswerProvider
    private var visibleAnswerRecords: Set<String> = []
    private(set) var callAnswers: [String: CRMIncomingCallAnswer] = [:]
    private(set) var answerLookupFailed = false
    var answerRefreshRequest = 0
    @ObservationIgnored private var answerGeneration = -1

    init(gatewaySettings: CRMGatewaySettings? = nil, answerProvider: any CRMCallAnswerProvider = CRMGatewayClient()) {
        self.gatewaySettings = gatewaySettings
        self.answerProvider = answerProvider
    }

    struct AnswerContext: Hashable {
        let generation: Int
        let refresh: Int
        let calls: [CRMIncomingCallRequest]
    }
    var answerContext: AnswerContext {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let calls = gatewaySettings?.enabled == true ? records.compactMap { record -> CRMIncomingCallRequest? in
            guard record.isIncoming, record.isMissed, visibleAnswerRecords.contains(record.id),
                  let date = record.startedAt, let raw = record.callerNumber, let phone = CRMPhoneNumber.normalize(raw) else { return nil }
            return CRMIncomingCallRequest(id: record.id, phoneNumber: phone, startedAt: formatter.string(from: date))
        } : []
        return AnswerContext(generation: gatewaySettings?.generation ?? 0, refresh: answerRefreshRequest, calls: calls)
    }
    func setAnswerRecordVisible(_ id: String, visible: Bool) {
        if visible { visibleAnswerRecords.insert(id) } else { visibleAnswerRecords.remove(id) }
    }
    func refreshCallAnswers() async {
        let context = answerContext
        if answerGeneration != context.generation {
            callAnswers.removeAll()
            answerGeneration = context.generation
        }
        guard let gatewaySettings, !context.calls.isEmpty else {
            if gatewaySettings?.enabled != true { callAnswers.removeAll() }
            return
        }
        do {
            // Collect rows appearing in one scrolling/layout pass into bounded batches.
            try await Task.sleep(for: .milliseconds(350))
            let configuration = try await gatewaySettings.configuration()
            guard context == answerContext else { return }
            answerLookupFailed = false
            // One UTC day spans at most two upstream calendar days. Keeping batches
            // within it avoids a request per row and handles arbitrary history dates.
            let groups = Dictionary(grouping: context.calls) { String($0.startedAt.prefix(10)) }
            for day in groups.keys.sorted() {
                let calls = groups[day] ?? []
                for start in stride(from: 0, to: calls.count, by: 25) {
                    let batch = Array(calls[start..<min(start + 25, calls.count)])
                    let answers = try await answerProvider.incomingCallAnswers(calls: batch, configuration: configuration)
                    try Task.checkCancellation()
                    guard context == answerContext else { return }
                    for answer in answers { callAnswers[answer.id] = answer }
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, context == answerContext else { return }
            // A failed read never becomes "nobody answered" or a stale employee.
            for call in context.calls { callAnswers.removeValue(forKey: call.id) }
            answerLookupFailed = true
        }
    }
    var filter: CallHistoryFilter = .all {
        didSet {
            guard oldValue != filter else { return }
            rebuildVisibleRecords()
        }
    }

    var query = "" {
        didSet {
            guard oldValue != query else { return }
            rebuildVisibleRecords()
        }
    }

    var selection: String?
    var pendingDeletion: CallHistoryDeletion?
    var searchFocusRequest = 0

    private(set) var allRecords: [PresentationCallHistoryRecord] = []
    private(set) var records: [PresentationCallHistoryRecord] = []

    var selectedRecord: PresentationCallHistoryRecord? {
        guard let selection else { return nil }
        return records.first { $0.identifier == selection }
    }

    func show(_ records: [PresentationCallHistoryRecord]) {
        let previous = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.id, $0) })
        let unchanged = Set(records.filter { previous[$0.id] == $0 }.map(\.id))
        callAnswers = callAnswers.filter { unchanged.contains($0.key) }
        visibleAnswerRecords.formIntersection(Set(records.map(\.id)))
        allRecords = records
        rebuildVisibleRecords()
    }

    func selectAndCall(
        _ record: PresentationCallHistoryRecord,
        action: (String) -> Void
    ) {
        selection = record.identifier
        action(record.identifier)
    }

    func callSelected(action: (String) -> Void) -> Bool {
        guard let record = selectedRecord else { return false }
        action(record.identifier)
        return true
    }

    func requestDeleteSelected() -> Bool {
        guard let record = selectedRecord else { return false }
        pendingDeletion = .record(record)
        return true
    }

    func requestDeleteAll() -> Bool {
        guard !allRecords.isEmpty else { return false }
        pendingDeletion = .all
        return true
    }

    func commitPendingDeletion(
        deleteRecord: (String) -> Void,
        deleteAll: () -> Void
    ) {
        guard let pendingDeletion else { return }
        self.pendingDeletion = nil

        switch pendingDeletion {
        case .record(let record):
            callAnswers.removeValue(forKey: record.id)
            visibleAnswerRecords.remove(record.id)
            allRecords.removeAll { $0.identifier == record.identifier }
            rebuildVisibleRecords()
            deleteRecord(record.identifier)
        case .all:
            callAnswers.removeAll()
            visibleAnswerRecords.removeAll()
            allRecords.removeAll()
            records.removeAll()
            selection = nil
            deleteAll()
        }
    }

    func requestSearchFocus() {
        searchFocusRequest &+= 1
    }

    private func rebuildVisibleRecords() {
        let filteredByKind = allRecords.filter(filter.matches)
        let trimmedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if trimmedQuery.isEmpty {
            records = filteredByKind
        } else {
            records = filteredByKind.filter {
                $0.matchesSearch(trimmedQuery)
            }
        }

        normalizeSelection()
    }

    private func normalizeSelection() {
        guard let selection else { return }
        guard records.contains(where: { $0.identifier == selection }) else {
            self.selection = nil
            return
        }
    }
}
