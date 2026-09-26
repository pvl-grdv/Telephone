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
            allRecords.removeAll { $0.identifier == record.identifier }
            rebuildVisibleRecords()
            deleteRecord(record.identifier)
        case .all:
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
