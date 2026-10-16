//
//  CRMCustomerInventoryView.swift
//  Telephone
//

import Foundation
import SwiftUI

/// Native, single-pane macOS inventory. Gateway records are immutable here.
struct CRMCustomerInventoryView: View {
    let customer: CRMKeyLookupCustomer

    var body: some View {
        CRMInventoryPreparationView(customer: customer)
            .equatable()
    }
}

/// Group and sort once per distinct gateway response. Search never regroups
/// source records and runs off the main actor after input debouncing.
private struct CRMInventoryPreparationView: View, Equatable {
    let customer: CRMKeyLookupCustomer

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.customer == rhs.customer
    }

    var body: some View {
        CRMInventoryBrowserView(
            customer: customer,
            preparedInventory: CRMInventoryPresentation(customer: customer)
        )
    }
}

private struct CRMInventoryBrowserView: View {
    let customer: CRMKeyLookupCustomer
    let preparedInventory: CRMInventoryPresentation

    private struct SearchRequest: Equatable {
        let customer: CRMKeyLookupCustomer
        let text: String
    }

    private struct SearchResult {
        let query: String
        let inventory: CRMInventoryPresentation
    }

    @State private var searchText = ""
    @State private var searchResult: SearchResult?
    @State private var selectedKey = 0
    @State private var selectedRows: Set<CRMInventoryPresentation.Row.ID> = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isFiltering = !query.isEmpty && searchResult?.query != searchText
        let inventory = query.isEmpty ? preparedInventory :
            (searchResult?.query == searchText ? (searchResult?.inventory ?? preparedInventory) : preparedInventory)
        let rows = inventory.rows(for: selectedKey == 0 ? nil : selectedKey)

        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                companyHeader
                Text(selectedKey == 0 && !inventory.isFiltered
                     ? String(
                         format: NSLocalizedString("%ld keys · %ld programs · %ld records", comment: "Inventory counts."),
                         inventory.visibleKeyCount, inventory.visibleProgramGroupCount, inventory.visibleRecordCount
                     )
                     : String(
                         format: NSLocalizedString("%ld of %ld records", comment: "Visible CRM records after filtering."),
                         rows.count, inventory.totalRecordCount
                     ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("crm.inventory.counts")

                HStack(spacing: 10) {
                    Picker(
                        NSLocalizedString("Filter by key", comment: "Inventory key filter."),
                        selection: $selectedKey
                    ) {
                        Text(NSLocalizedString("All keys", comment: "Show programs across every key."))
                            .tag(0)
                        ForEach(preparedInventory.keys) { key in
                            Text("\(key.id) · \(DisplayNameText.normalized(key.key.name))")
                                .tag(key.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 210)
                    .accessibilityIdentifier("crm.inventory.keyFilter")

                    TextField(
                        NSLocalizedString("Search keys, programs or versions", comment: "Global inventory search."),
                        text: $searchText
                    )
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .accessibilityIdentifier("crm.inventory.search")
                    .frame(maxWidth: .infinity)

                    if isFiltering {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel(
                                NSLocalizedString("Searching CRM…", comment: "CRM lookup loading status.")
                            )
                    }
                }
                programTable(rows)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("crm.inventory.programs")
                    .overlay {
                        if rows.isEmpty && !isFiltering {
                            ContentUnavailableView(
                                inventory.isFiltered
                                    ? NSLocalizedString("No matching keys or programs", comment: "Empty inventory search.")
                                    : NSLocalizedString("No programs on this key.", comment: "Empty inventory table."),
                                systemImage: "magnifyingglass"
                            )
                        }
                    }

                Text(NSLocalizedString("Versions and releases: higher numbers first", comment: "Ordering, not license status."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
        .task(id: SearchRequest(customer: customer, text: searchText)) {
            let input = searchText
            guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                searchResult = nil
                return
            }
            // Keep expensive matching/group projection off the UI thread, and
            // coalesce bursts of typing. Superseded results are ignored.
            do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
            let prepared = preparedInventory
            let filtered = await Task.detached(priority: .userInitiated) {
                prepared.filtering(input)
            }.value
            guard !Task.isCancelled else { return }
            searchResult = SearchResult(query: input, inventory: filtered)
        }
        .onChange(of: searchText) {
            selectedRows.removeAll()
        }
        .onChange(of: selectedKey) {
            selectedRows.removeAll()
        }
    }

    private var companyHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                Text(DisplayNameText.normalized(customer.company.name))
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(NSLocalizedString("Registration number", comment: "Organization registration number label."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(customer.company.formattedCode)
                        .font(.callout.monospacedDigit())
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            }
            if let phones = customer.company.phones, !phones.isEmpty {
                Text(phones.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }

    private func programTable(_ rows: [CRMInventoryPresentation.Row]) -> some View {
        Table(rows, selection: $selectedRows) {
            TableColumn(NSLocalizedString("Program", comment: "Inventory program column.")) { row in
                Link(destination: row.program.keyUrl) {
                    Text(row.program.name.isEmpty
                         ? NSLocalizedString("Unnamed program", comment: "Unnamed program.")
                         : DisplayNameText.normalized(row.program.name))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .help(DisplayNameText.normalized(row.program.name))
            }.width(min: 180, ideal: 320)
            TableColumn(NSLocalizedString("Version", comment: "Inventory version column.")) { row in
                Text(display(row.program.version))
                    .monospacedDigit()
                    .textSelection(.enabled)
            }.width(min: 72, ideal: 92, max: 130)
            TableColumn(NSLocalizedString("Release", comment: "Inventory release column.")) { row in
                Text(display(row.program.release))
                    .monospacedDigit()
                    .textSelection(.enabled)
            }.width(min: 72, ideal: 92, max: 130)
            TableColumn(NSLocalizedString("Key", comment: "Compact inventory key column.")) { row in
                Link(String(row.key.id), destination: row.key.url)
                    .monospacedDigit()
            }.width(min: 78, ideal: 90, max: 140)
        }
        .copyable(rows.filter { selectedRows.contains($0.id) }.map { row in
            [String(row.key.id), DisplayNameText.normalized(row.program.name),
             display(row.program.version), display(row.program.release)]
                .joined(separator: "\t")
        })
    }

    private func display(_ value: String?) -> String {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "—" : text
    }
}
