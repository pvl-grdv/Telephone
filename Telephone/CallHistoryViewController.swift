//
//  CallHistoryViewController.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

import Cocoa
import Observation
import SwiftUI

enum CallHistoryFilter: Int, CaseIterable, Hashable {
    case all
    case missed
    case incoming
    case outgoing

    var title: String {
        switch self {
        case .all:
            return NSLocalizedString("All", comment: "All call history filter.")
        case .missed:
            return NSLocalizedString("Missed", comment: "Missed call history filter.")
        case .incoming:
            return NSLocalizedString("Incoming", comment: "Incoming call history filter.")
        case .outgoing:
            return NSLocalizedString("Outgoing", comment: "Outgoing call history filter.")
        }
    }

    func matches(_ record: PresentationCallHistoryRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .missed:
            return record.isMissed
        case .incoming:
            return record.isIncoming
        case .outgoing:
            return !record.isIncoming
        }
    }
}

private enum CallHistoryDeletion {
    case record(PresentationCallHistoryRecord)
    case all

    var title: String {
        switch self {
        case .record(let record):
            return String(
                format: NSLocalizedString(
                    "Are you sure you want to delete the record “%@”?",
                    comment: "Call history record removal alert."
                ),
                record.name
            )
        case .all:
            return NSLocalizedString(
                "Are you sure you want to delete all records?",
                comment: "Call history all records removal alert."
            )
        }
    }
}

@MainActor
@Observable
private final class CallHistoryViewModel {
    var filter: CallHistoryFilter = .all {
        didSet { normalizeSelection() }
    }
    var query = "" {
        didSet { normalizeSelection() }
    }
    var selection: String?
    var pendingDeletion: CallHistoryDeletion?
    var searchFocusRequest = 0

    private(set) var allRecords: [PresentationCallHistoryRecord] = []

    var records: [PresentationCallHistoryRecord] {
        let filteredByKind = allRecords.filter(filter.matches)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return filteredByKind }
        return filteredByKind.filter { $0.matchesSearch(trimmedQuery) }
    }

    var selectedRecord: PresentationCallHistoryRecord? {
        guard let selection else { return nil }
        return records.first { $0.identifier == selection }
    }

    func show(_ records: [PresentationCallHistoryRecord]) {
        allRecords = records
        normalizeSelection()
    }

    func selectAndCall(_ record: PresentationCallHistoryRecord, action: (String) -> Void) {
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
            normalizeSelection()
            deleteRecord(record.identifier)
        case .all:
            allRecords.removeAll()
            selection = nil
            deleteAll()
        }
    }

    func requestSearchFocus() {
        searchFocusRequest &+= 1
    }

    private func normalizeSelection() {
        let displayedRecords = records
        if let selection, displayedRecords.contains(where: { $0.identifier == selection }) {
            return
        }
        selection = displayedRecords.first?.identifier
    }
}

@MainActor
final class CallHistoryViewController: NSViewController {
    @objc var keyView: NSView {
        return view
    }

    @objc weak var target: CallHistoryViewEventTarget? {
        didSet {
            target?.shouldReloadData()
        }
    }

    @objc var recordCount: Int {
        return model.allRecords.count
    }

    private let model = CallHistoryViewModel()

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSHostingView(
            rootView: CallHistoryScreen(
                model: model,
                call: { [weak self] identifier in
                    self?.target?.didPickRecord(withIdentifier: identifier)
                },
                copy: { [weak self] address in
                    self?.copyToPasteboard(address)
                },
                deleteRecord: { [weak self] identifier in
                    self?.target?.shouldRemoveRecord(withIdentifier: identifier)
                },
                deleteAll: { [weak self] in
                    self?.target?.shouldRemoveAllRecords()
                }
            )
        )
    }

    @objc func updateNextKeyView(_ view: NSView) {
        keyView.nextKeyView = view
    }

    @objc func focusCallHistorySearch(_ sender: Any?) {
        model.requestSearchFocus()
    }

    @IBAction func makeCall(_ sender: Any?) {
        _ = model.callSelected { [weak self] identifier in
            self?.target?.didPickRecord(withIdentifier: identifier)
        }
    }

    @IBAction func copy(_ sender: Any?) {
        guard let address = model.selectedRecord?.contact.address else { return }
        copyToPasteboard(address)
    }

    @IBAction func delete(_ sender: Any?) {
        _ = model.requestDeleteSelected()
    }

    @IBAction func deleteAll(_ sender: Any?) {
        _ = model.requestDeleteAll()
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

extension CallHistoryViewController: CallHistoryView {
    func show(_ records: [PresentationCallHistoryRecord]) {
        model.show(records)
    }
}

extension CallHistoryViewController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(focusCallHistorySearch(_:)):
            return true
        case #selector(copy(_:)), #selector(makeCall(_:)), #selector(delete(_:)):
            return model.selectedRecord != nil
        case #selector(deleteAll(_:)):
            return !model.allRecords.isEmpty
        default:
            return false
        }
    }
}

private struct CallHistoryScreen: View {
    @Bindable var model: CallHistoryViewModel
    @FocusState private var searchFocused: Bool
    @FocusState private var historyFocused: Bool

    let call: (String) -> Void
    let copy: (String) -> Void
    let deleteRecord: (String) -> Void
    let deleteAll: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
        }
        .alert(model.pendingDeletion?.title ?? "", isPresented: deletionIsPresented) {
            Button(NSLocalizedString("Delete", comment: "Delete button."), role: .destructive) {
                model.commitPendingDeletion(deleteRecord: deleteRecord, deleteAll: deleteAll)
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel button."), role: .cancel) {
                model.pendingDeletion = nil
            }
        } message: {
            Text(
                NSLocalizedString(
                    "This action cannot be undone.",
                    comment: "Call history record removal alert informative text."
                )
            )
        }
        .onChange(of: model.searchFocusRequest) {
            searchFocused = true
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker(
                NSLocalizedString("Filter", comment: "Call history filter picker label."),
                selection: $model.filter
            ) {
                ForEach(CallHistoryFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .frame(width: 112)

            TextField(
                NSLocalizedString("Search Call History", comment: "Call history search field placeholder."),
                text: $model.query
            )
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
        }
        .padding(8)
    }

    @ViewBuilder
    private var content: some View {
        if model.records.isEmpty {
            ContentUnavailableView {
                Label(
                    model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? NSLocalizedString("No Calls", comment: "Empty call history title.")
                        : NSLocalizedString("No Results", comment: "Call history search has no matches title."),
                    systemImage: "phone"
                )
            } description: {
                Text(
                    model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? NSLocalizedString("Your call history will appear here.", comment: "Empty call history description.")
                        : NSLocalizedString("Try a different search or filter.", comment: "Empty call history search description.")
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.records, id: \.identifier) { record in
                        CallHistoryRow(
                            record: record,
                            isSelected: model.selection == record.identifier
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.selection = record.identifier
                            historyFocused = true
                        }
                        .onTapGesture(count: 2) {
                            model.selectAndCall(record, action: call)
                        }
                        .contextMenu {
                            Button(NSLocalizedString("Call Number", comment: "Call history context menu item.")) {
                                model.selectAndCall(record, action: call)
                            }
                            Button(NSLocalizedString("Copy Number", comment: "Call history context menu item.")) {
                                copy(record.contact.address)
                            }
                            Divider()
                            Button(
                                NSLocalizedString("Delete…", comment: "Call history context menu item."),
                                role: .destructive
                            ) {
                                model.selection = record.identifier
                                _ = model.requestDeleteSelected()
                            }
                            Button(
                                NSLocalizedString("Delete All…", comment: "Call history context menu item."),
                                role: .destructive
                            ) {
                                _ = model.requestDeleteAll()
                            }
                        }

                        Divider()
                            .padding(.leading, 32)
                    }
                }
                .padding(.horizontal, 8)
            }
            .focusable()
            .focused($historyFocused)
            .onMoveCommand(perform: moveSelection)
            .onKeyPress(.return) {
                model.callSelected(action: call) ? .handled : .ignored
            }
            .onKeyPress(.delete) {
                model.requestDeleteSelected() ? .handled : .ignored
            }
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let records = model.records
        guard !records.isEmpty else { return }

        let currentIndex = model.selection.flatMap { selection in
            records.firstIndex { $0.identifier == selection }
        } ?? 0

        switch direction {
        case .up:
            model.selection = records[max(0, currentIndex - 1)].identifier
        case .down:
            model.selection = records[min(records.count - 1, currentIndex + 1)].identifier
        default:
            break
        }
    }

    private var deletionIsPresented: Binding<Bool> {
        Binding(
            get: { model.pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    model.pendingDeletion = nil
                }
            }
        )
    }
}

private struct CallHistoryRow: View {
    let record: PresentationCallHistoryRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if record.isIncoming {
                    Color.clear
                } else {
                    Image(systemName: "phone.arrow.up.right.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.contact.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color(nsColor: record.contact.color))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(record.contact.tooltip)

                Text(record.contact.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: 14, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(record.date)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(record.duration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: 14, alignment: .trailing)
            }
            .frame(width: 120, alignment: .trailing)
        }
        .frame(height: 44)
        .padding(.horizontal, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.14))
            }
        }
    }
}
