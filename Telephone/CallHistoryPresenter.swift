//
//  CallHistoryPresenter.swift
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
        guard let selection else { return }
        guard records.contains(where: { $0.identifier == selection }) else {
            self.selection = nil
            return
        }
    }
}

extension FocusedValues {
    @Entry var callHistoryPresenter: CallHistoryPresenter?
}

@MainActor
final class CallHistoryPresenter: CallHistoryView {
    weak var target: CallHistoryViewEventTarget? {
        didSet {
            target?.shouldReloadData()
        }
    }

    var recordCount: Int {
        model.allRecords.count
    }

    var hasSelection: Bool {
        model.selectedRecord != nil
    }

    var hasRecords: Bool {
        !model.allRecords.isEmpty
    }

    private let model = CallHistoryViewModel()
    private let clipboard: Clipboard

    init(clipboard: Clipboard = SystemClipboard.shared) {
        self.clipboard = clipboard
    }

    var contentView: some View {
        CallHistoryScreen(
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
    }

    func show(_ records: [PresentationCallHistoryRecord]) {
        model.show(records)
    }

    func focusSearch() {
        model.requestSearchFocus()
    }

    private func copyToPasteboard(_ value: String) {
        clipboard.copy(value)
    }
}

private struct CallHistoryScreen: View {
    @Bindable var model: CallHistoryViewModel
    @FocusState private var searchFocused: Bool

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
            CallHistoryFilterMenu(selection: $model.filter)

            TextField(
                NSLocalizedString(
                    "Search Call History",
                    comment: "Call history search field placeholder."
                ),
                text: $model.query
            )
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if model.records.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $model.selection) {
                ForEach(model.records) { record in
                    CallHistoryRow(record: record)
                        .tag(record.identifier)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            model.selectAndCall(record, action: call)
                        }
                        .contextMenu {
                            Button(
                                NSLocalizedString(
                                    "Call Number",
                                    comment: "Call history context menu item."
                                )
                            ) {
                                model.selectAndCall(record, action: call)
                            }

                            Button(
                                NSLocalizedString(
                                    "Copy Number",
                                    comment: "Call history context menu item."
                                )
                            ) {
                                copy(record.contact.address)
                            }

                            Divider()

                            Button(
                                NSLocalizedString(
                                    "Delete…",
                                    comment: "Call history context menu item."
                                ),
                                role: .destructive
                            ) {
                                model.selection = record.identifier
                                _ = model.requestDeleteSelected()
                            }

                            Button(
                                NSLocalizedString(
                                    "Delete All…",
                                    comment: "Call history context menu item."
                                ),
                                role: .destructive
                            ) {
                                _ = model.requestDeleteAll()
                            }
                        }
                }
            }
            .listStyle(.inset)
            .onCopyCommand(perform: copyCommandPayload)
            .onKeyPress(.return) {
                model.callSelected(action: call) ? .handled : .ignored
            }
            .onDeleteCommand {
                _ = model.requestDeleteSelected()
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let query = model.query.trimmingCharacters(in: .whitespacesAndNewlines)

        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if model.filter != .all {
            ContentUnavailableView {
                Label(
                    NSLocalizedString(
                        "No Matching Calls",
                        comment: "Call history filter has no matches title."
                    ),
                    systemImage: "phone"
                )
            } description: {
                Text(
                    NSLocalizedString(
                        "Try a different call filter.",
                        comment: "Call history filter has no matches description."
                    )
                )
            }
        } else {
            ContentUnavailableView {
                Label(
                    NSLocalizedString("No Calls", comment: "Empty call history title."),
                    systemImage: "phone"
                )
            } description: {
                Text(
                    NSLocalizedString(
                        "Your call history will appear here.",
                        comment: "Empty call history description."
                    )
                )
            }
        }
    }

    private var copyCommandPayload: (() -> [NSItemProvider])? {
        guard let address = model.selectedRecord?.contact.address else {
            return nil
        }

        return {
            [NSItemProvider(object: address as NSString)]
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

private struct CallHistoryFilterMenu: View {
    @Binding var selection: CallHistoryFilter

    var body: some View {
        Menu {
            ForEach(CallHistoryFilter.allCases, id: \.self) { filter in
                Button {
                    selection = filter
                } label: {
                    if selection == filter {
                        Label(filter.title, systemImage: "checkmark")
                    } else {
                        Text(filter.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)

                Text(selection.title)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 112, alignment: .leading)
        .help(NSLocalizedString("Filter Call History", comment: "Call history filter help."))
        .accessibilityLabel(
            NSLocalizedString("Filter Call History", comment: "Call history filter accessibility label.")
        )
        .accessibilityValue(selection.title)
    }
}

private struct CallHistoryRow: View {
    let record: PresentationCallHistoryRecord

    private var directionSymbol: String {
        record.isIncoming
            ? "phone.arrow.down.left.fill"
            : "phone.arrow.up.right.fill"
    }

    private var statusText: String {
        record.isMissed
            ? NSLocalizedString("Missed", comment: "Missed call history status.")
            : record.duration
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: directionSymbol)
                .font(.caption)
                .foregroundStyle(record.isMissed ? Color.red : Color.secondary)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.contact.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(record.isMissed ? Color.red : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(record.contact.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: 14, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(record.date)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(record.isMissed ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .frame(height: 14, alignment: .trailing)
            }
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .help(record.contact.address)
        .accessibilityElement(children: .combine)
    }
}


struct CallHistoryCommands: Commands {
    @FocusedValue(\.callHistoryPresenter)
    private var presenter

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button(
                NSLocalizedString(
                    "Find…",
                    comment: "Focus call history search menu item."
                )
            ) {
                presenter?.focusSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(presenter == nil)
        }
    }
}
