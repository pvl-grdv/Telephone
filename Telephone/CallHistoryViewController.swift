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

enum CallHistoryFilter: Int, CaseIterable {
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

final class CallHistoryViewController: NSViewController {
    @objc var keyView: NSView {
        return tableView
    }
    @objc weak var target: CallHistoryViewEventTarget? {
        didSet {
            target?.shouldReloadData()
        }
    }
    var recordCount: Int {
        return allRecords.count
    }
    private var allRecords: [PresentationCallHistoryRecord] = []
    private var records: [PresentationCallHistoryRecord] = []
    private let pasteboard = NSPasteboard.general
    private let searchField = NSSearchField()
    private let filterButton = NSPopUpButton(frame: .zero, pullsDown: false)
    @IBOutlet private weak var tableView: NSTableView!

    init() {
        super.init(nibName: "CallHistoryViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installSearchField()
        target?.shouldReloadData()
    }

    override func keyDown(with event: NSEvent) {
        if isReturnKey(event) {
            pickRecord(at: tableView.selectedRow)
        } else if isDeleteKey(event) {
            removeRecord(at: tableView.selectedRow)
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func updateNextKeyView(_ view: NSView) {
        keyView.nextKeyView = view
    }

    @objc private func searchHistory(_ sender: NSSearchField) {
        updateDisplayedRecords(allRecords)
    }

    @objc private func filterHistory(_ sender: NSPopUpButton) {
        updateDisplayedRecords(allRecords)
    }

    @objc func focusCallHistorySearch(_ sender: Any?) {
        view.window?.makeFirstResponder(searchField)
    }

    @IBAction func didDoubleClick(_ sender: NSTableView) {
        guard sender.clickedRow != -1 else { return }
        pickRecord(at: sender.clickedRow)
    }

    @IBAction func makeCall(_ sender: Any) {
        pickRecord(at: clickedOrSelectedRow())
    }

    @IBAction func copy(_ sender: Any) {
        let row = clickedOrSelectedRow()
        guard records.indices.contains(row) else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects([records[row]])
    }

    @IBAction func delete(_ sender: Any) {
        removeRecord(at: clickedOrSelectedRow())
    }

    @IBAction func deleteAll(_ sender: Any) {
        Task {
            if await makeDeleteAllAlert().beginSheetModal(for: view.window!) == .alertFirstButtonReturn {
                target?.shouldRemoveAllRecords()
            }
        }
    }
}

private extension CallHistoryViewController {
    func installSearchField() {
        guard let scrollView = tableView.enclosingScrollView else { return }

        filterButton.addItems(withTitles: CallHistoryFilter.allCases.map(\.title))
        filterButton.selectItem(at: CallHistoryFilter.all.rawValue)
        filterButton.target = self
        filterButton.action = #selector(filterHistory(_:))
        filterButton.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = NSLocalizedString("Search Call History", comment: "Call history search field placeholder.")
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchHistory(_:))
        searchField.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filterButton)
        view.addSubview(searchField)

        NSLayoutConstraint.activate([
            filterButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            filterButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            filterButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: filterButton.trailingAnchor, constant: 6),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func updateDisplayedRecords(_ source: [PresentationCallHistoryRecord]) {
        let filter = CallHistoryFilter(rawValue: filterButton.indexOfSelectedItem) ?? .all
        let filteredByKind = source.filter(filter.matches)
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? filteredByKind : filteredByKind.filter { record in
            record.matchesSearch(query)
        }

        let oldRecords = records
        let oldIndex = tableView.selectedRow
        let selectedIdentifier = records.indices.contains(oldIndex) ? records[oldIndex].identifier : nil
        records = filtered
        reloadTableView(old: oldRecords, new: filtered)
        restoreSelection(
            oldIndex: oldIndex,
            old: oldRecords,
            new: filtered,
            selectedIdentifier: selectedIdentifier
        )
    }

    func pickRecord(at index: Int) {
        guard records.indices.contains(index) else { return }
        target?.didPickRecord(withIdentifier: records[index].identifier)
    }

    func removeRecord(at index: Int) {
        guard records.indices.contains(index) else { return }
        let record = records[index]
        Task {
            if await makeDeleteRecordAlert(recordName: record.name).beginSheetModal(for: view.window!) == .alertFirstButtonReturn {
                removeTableViewRow(index, andRecordWithIdentifier: record.identifier)
            }
        }
    }

    func isReturnKey(_ event: NSEvent) -> Bool {
        return event.keyCode == 0x24
    }

    func isDeleteKey(_ event: NSEvent) -> Bool {
        return event.keyCode == 0x33 || event.keyCode == 0x75
    }

    func removeTableViewRow(_ row: Int, andRecordWithIdentifier identifier: String) {
        guard records.indices.contains(row) else { return }
        tableView.removeRows(at: IndexSet(integer: row), withAnimation: .slideUp)
        records.remove(at: row)
        allRecords.removeAll { $0.identifier == identifier }
        target?.shouldRemoveRecord(withIdentifier: identifier)
    }

    func clickedOrSelectedRow() -> Int {
        return tableView.clickedRow != -1 ? tableView.clickedRow : tableView.selectedRow
    }
}

extension CallHistoryViewController: CallHistoryView {
    func show(_ records: [PresentationCallHistoryRecord]) {
        allRecords = records
        updateDisplayedRecords(records)
    }

    private func reloadTableView(old: [PresentationCallHistoryRecord], new: [PresentationCallHistoryRecord]) {
        let diff = ArrayDifference(before: old, after: new)
        if case .prepended(count: let count) = diff, count <= 2 {
            tableView.insertRows(at: IndexSet(integersIn: 0..<count), withAnimation: .slideDown)
        } else if case .shiftedByOne = diff {
            tableView.beginUpdates()
            tableView.insertRows(at: IndexSet(integer: 0), withAnimation: .slideDown)
            tableView.removeRows(at: IndexSet(integer: old.count), withAnimation: .slideDown)
            tableView.endUpdates()
        } else {
            tableView.reloadData()
        }
    }

    private func restoreSelection(
        oldIndex: Int,
        old: [PresentationCallHistoryRecord],
        new: [PresentationCallHistoryRecord],
        selectedIdentifier: String?
    ) {
        guard !records.isEmpty else { return }

        let index: Int
        if let selectedIdentifier,
           let preservedIndex = new.firstIndex(where: { $0.identifier == selectedIdentifier }) {
            index = preservedIndex
        } else {
            index = RestoredSelectionIndex(indexBefore: oldIndex, before: old, after: new).value
        }

        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }
}

extension CallHistoryViewController: NSSearchFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }

        if !searchField.stringValue.isEmpty {
            searchField.stringValue = ""
            updateDisplayedRecords(allRecords)
        } else {
            view.window?.makeFirstResponder(tableView)
        }
        return true
    }
}

extension CallHistoryViewController: NSTableViewDataSource {
    func numberOfRows(in view: NSTableView) -> Int {
        return records.count
    }

    func tableView(_ view: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
        return records[row]
    }
}

extension CallHistoryViewController: NSTableViewDelegate {
    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSeparators()
    }

    func tableViewSelectionIsChanging(_ notification: Notification) {
        updateSeparators()
    }

    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        switch edge {
        case .trailing:
            return [makeDeleteAction()]
        case .leading:
            return []
        @unknown default:
            return []
        }
    }

    private func updateSeparators() {
        tableView.enumerateAvailableRowViews { (view, _) in
            view.needsDisplay = true
        }
    }

    private func makeDeleteAction() -> NSTableViewRowAction {
        let a = NSTableViewRowAction(
            style: .destructive,
            title: NSLocalizedString("Delete", comment: "Delete button."),
            handler: removeRowAndRecord
        )
        a.image = NSImage(named: NSImage.touchBarDeleteTemplateName)
        return a
    }

    private func removeRowAndRecord(action: NSTableViewRowAction, row: Int) {
        guard records.indices.contains(row) else { return }
        removeTableViewRow(row, andRecordWithIdentifier: records[row].identifier)
    }
}

extension CallHistoryViewController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(focusCallHistorySearch):
            return true
        case #selector(copy(_:)), #selector(makeCall), #selector(delete):
            return records.indices.contains(clickedOrSelectedRow())
        case #selector(deleteAll):
            return !allRecords.isEmpty
        default:
            return false
        }
    }
}

@MainActor
private func makeDeleteRecordAlert(recordName name: String) -> NSAlert {
    return makeDeletionAlert(
        messageText: String(
            format: NSLocalizedString(
                "Are you sure you want to delete the record “%@”?", comment: "Call history record removal alert."
            ),
            name
        )
    )
}

@MainActor
private func makeDeleteAllAlert() -> NSAlert {
    return makeDeletionAlert(
        messageText: NSLocalizedString(
            "Are you sure you want to delete all records?", comment: "Call history all records removal alert."
        )
    )
}

@MainActor
private func makeDeletionAlert(messageText text: String) -> NSAlert {
    let a = NSAlert()
    a.messageText = text
    a.informativeText = NSLocalizedString(
        "This action cannot be undone.", comment: "Call history record removal alert informative text."
    )
    let delete = a.addButton(withTitle: NSLocalizedString("Delete", comment: "Delete button."))
    delete.hasDestructiveAction = true
    a.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button.")).keyEquivalent = "\u{1b}"
    return a
}
