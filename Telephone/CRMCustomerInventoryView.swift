//
//  CRMCustomerInventoryView.swift
//  Telephone
//

import Foundation
import SwiftUI

/// Shared browser inventory for live calls and saved history checks.
/// Gateway records are immutable here; searching and selection are local.
struct CRMCustomerInventoryView: View {
    let customer: CRMKeyLookupCustomer

    var body: some View {
        CRMInventoryPreparationView(customer: customer)
            .equatable()
    }
}

/// Prepare record groups only when gateway data changes; searching and
/// row selection remain local to the browser.
private struct CRMInventoryPreparationView: View, Equatable {
    let customer: CRMKeyLookupCustomer

    var body: some View {
        CRMInventoryBrowserView(
            customer: customer,
            preparedInventory: CRMInventoryPresentation(customer: customer)
        )
    }
}

/// Full-height desktop inventory, sharing the prepared records with live calls.
private struct CRMInventoryBrowserView: View {
    let customer: CRMKeyLookupCustomer
    let preparedInventory: CRMInventoryPresentation
    @State private var searchText = ""
    // Zero means all keys; gateway key IDs are strictly positive.
    @State private var selectedKey: Int? = 0
    @State private var selectedRows: Set<CRMInventoryPresentation.Row.ID> = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        let inventory = preparedInventory.filtering(searchText)
        let keyID = selectedKey == 0 ? nil : selectedKey
        let rows = inventory.rows(for: keyID)
        // The navigation split view owns search and the detail's safe area.
        // Keeping it at the root prevents clipped first rows in history windows.
        NavigationSplitView {
            List(selection: $selectedKey) {
                Text(NSLocalizedString("All keys", comment: "Show programs across every key."))
                    .tag(0).accessibilityIdentifier("crm.inventory.allKeys")
                ForEach(inventory.keys) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(item.id)).monospacedDigit()
                        Text(DisplayNameText.normalized(item.key.name)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .tag(item.id)
                    .accessibilityIdentifier("crm.inventory.key.\(item.id)")
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 185, max: 220)
        } detail: {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(DisplayNameText.normalized(customer.company.name))
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(customer.company.formattedCode)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        // Keep the familiar ⌘F shortcut while SwiftUI owns the search field.
                        Button {
                            searchFocused = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .keyboardShortcut("f", modifiers: .command)
                        .help(NSLocalizedString("Search keys, programs or versions", comment: "Global inventory search."))
                        .accessibilityLabel(NSLocalizedString("Search keys, programs or versions", comment: "Global inventory search."))
                    }

                    if let phones = customer.company.phones, !phones.isEmpty {
                        Text(phones.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }

                    Text(String(format: NSLocalizedString("%ld keys · %ld programs · %ld records", comment: "Inventory counts."),
                                inventory.visibleKeyCount, inventory.visibleProgramGroupCount, inventory.visibleRecordCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("crm.inventory.counts")
                }
                if let key = inventory.keys.first(where: { $0.id == keyID }) {
                    HStack {
                        Text(DisplayNameText.normalized(key.key.name)).font(.callout.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Link(NSLocalizedString("Personal account", comment: "Open key portal."), destination: key.key.url)
                    }.padding(.horizontal, 8)
                }
                GeometryReader { geometry in
                    // Size from the detail pane, including sidebar resizing.
                    // Prefer the native, column-headed table whenever
                    // all four columns fit. Reserve cards for the smallest
                    // detail panes instead of switching at ordinary widths.
                    if geometry.size.width >= 460 {
                        programTable(rows)
                    } else {
                        compactPrograms(rows, showsKeyNumber: keyID == nil)
                    }
                }
                .copyable(rows.filter { selectedRows.contains($0.id) }.map { row in
                    [String(row.key.id), DisplayNameText.normalized(row.program.name), display(row.program.version), display(row.program.release)].joined(separator: "\t")
                })
                .accessibilityIdentifier("crm.inventory.programs")
                .overlay {
                    if rows.isEmpty {
                        Text(NSLocalizedString(inventory.isFiltered ? "No matching keys or programs" : "No programs on this key.", comment: "Empty inventory table."))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(NSLocalizedString("Versions and releases: higher numbers first", comment: "Ordering, not license status."))
                    .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(
            text: $searchText,
            placement: .sidebar,
            prompt: Text(NSLocalizedString("Search keys, programs or versions", comment: "Global inventory search."))
        )
        .searchFocused($searchFocused)
        .onChange(of: searchText) { selectedKey = 0; selectedRows = [] }
        .onChange(of: customer.sourceKeyId) { searchText = ""; selectedKey = 0; selectedRows = [] }
        .onChange(of: inventory.keys.map(\.id)) {
            selectedKey = inventory.retainedKeySelection(selectedKey)
        }
        .onChange(of: rows.map(\.id)) {
            selectedRows.formIntersection(rows.map(\.id))
        }
    }

    private func programTable(_ rows: [CRMInventoryPresentation.Row]) -> some View {
        Table(rows, selection: $selectedRows) {
            TableColumn(NSLocalizedString("Program", comment: "Inventory program column.")) { row in
                Link(destination: row.program.keyUrl) {
                    Text(row.program.name.isEmpty ? NSLocalizedString("Unnamed program", comment: "Unnamed program.") : DisplayNameText.normalized(row.program.name))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .help(DisplayNameText.normalized(row.program.name))
            }.width(min: 150, ideal: 240)
            TableColumn(NSLocalizedString("Version", comment: "Inventory version column.")) { row in
                Text(display(row.program.version)).monospacedDigit().textSelection(.enabled)
            }.width(92)
            TableColumn(NSLocalizedString("Release", comment: "Inventory release column.")) { row in
                Text(display(row.program.release)).monospacedDigit().textSelection(.enabled)
            }.width(92)
            TableColumn(NSLocalizedString("Key number", comment: "Inventory key column.")) { row in
                Link(String(row.key.id), destination: row.key.url).monospacedDigit()
            }.width(84)
        }
    }

    private func compactPrograms(
        _ rows: [CRMInventoryPresentation.Row],
        showsKeyNumber: Bool
    ) -> some View {
        List(rows, selection: $selectedRows) { row in
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Link(destination: row.program.keyUrl) {
                        Text(row.program.name.isEmpty ? NSLocalizedString("Unnamed program", comment: "Unnamed program.") : DisplayNameText.normalized(row.program.name))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .help(DisplayNameText.normalized(row.program.name))

                    Text("v" + display(row.program.version))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("\(NSLocalizedString("Version", comment: "Inventory version column.")): \(display(row.program.version))")
                        .help("\(NSLocalizedString("Version", comment: "Inventory version column.")): \(display(row.program.version))")

                    Text("r" + display(row.program.release))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("\(NSLocalizedString("Release", comment: "Inventory release column.")): \(display(row.program.release))")
                        .help("\(NSLocalizedString("Release", comment: "Inventory release column.")): \(display(row.program.release))")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsKeyNumber {
                    Link(destination: row.key.url) {
                        Label(String(row.key.id), systemImage: "key.horizontal")
                    }
                    .font(.caption)
                    .accessibilityLabel("\(NSLocalizedString("Key number", comment: "Inventory key column.")): \(row.key.id)")
                }
            }
            .padding(.vertical, 3)
            .tag(row.id)
        }
        .listStyle(.inset)
        .accessibilityIdentifier("crm.inventory.compactPrograms")
    }

    private func display(_ value: String?) -> String {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "—" : text
    }
}
