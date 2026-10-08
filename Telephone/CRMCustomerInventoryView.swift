//
//  CRMCustomerInventoryView.swift
//  Telephone
//

import Foundation
import SwiftUI

/// The same inventory presentation is used for a live call and a saved check.
/// All data comes from the gateway; this view only filters and displays it.
struct CRMCustomerInventoryView: View {
    let customer: CRMKeyLookupCustomer
    var scrollsInternally = false
    var usesBrowserLayout = false

    var body: some View {
        CRMInventoryPreparationView(customer: customer, scrollsInternally: scrollsInternally, usesBrowserLayout: usesBrowserLayout)
            .equatable()
    }
}

/// The equality boundary prepares groups only when gateway data changes.
/// Search and disclosure state belong to the child and cannot invalidate it.
private struct CRMInventoryPreparationView: View, Equatable {
    let customer: CRMKeyLookupCustomer
    let scrollsInternally: Bool
    let usesBrowserLayout: Bool

    var body: some View {
        if usesBrowserLayout {
            CRMInventoryBrowserView(customer: customer, preparedInventory: CRMInventoryPresentation(customer: customer))
        } else {
            CRMInventoryContentView(
                customer: customer,
                preparedInventory: CRMInventoryPresentation(customer: customer),
                scrollsInternally: scrollsInternally
            )
        }
    }
}

private struct CRMInventoryContentView: View {
    let customer: CRMKeyLookupCustomer
    let preparedInventory: CRMInventoryPresentation
    let scrollsInternally: Bool
    @State private var searchText = ""
    @State private var expandedKeys: Set<Int>

    init(customer: CRMKeyLookupCustomer, preparedInventory: CRMInventoryPresentation, scrollsInternally: Bool) {
        self.customer = customer
        self.preparedInventory = preparedInventory
        self.scrollsInternally = scrollsInternally
        let firstKey = customer.sourceKeyId ?? customer.keys.map(\.id).min()
        _expandedKeys = State(initialValue: Set(firstKey.map { [$0] } ?? []))
    }

    var body: some View {
        let inventory = preparedInventory.filtering(searchText)
        VStack(alignment: .leading, spacing: 10) {
            organization
            TextField(
                NSLocalizedString("Search keys, programs or versions", comment: "Filter gateway inventory locally."),
                text: $searchText
            )
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .accessibilityIdentifier("crm.inventory.search")

            HStack(alignment: .top) {
                Text(summary(inventory))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("crm.inventory.counts")
                Spacer(minLength: 8)
                if !inventory.keys.isEmpty {
                    Button(allExpanded(inventory)
                           ? NSLocalizedString("Collapse all", comment: "Collapse visible inventory keys.")
                           : NSLocalizedString("Expand all", comment: "Expand visible inventory keys.")) {
                        if allExpanded(inventory) {
                            expandedKeys.subtract(inventory.keys.map(\.id))
                        } else {
                            expandedKeys.formUnion(inventory.keys.map(\.id))
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            Text(NSLocalizedString("Versions and releases: higher numbers first", comment: "Display order, not license status."))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if inventory.totalKeyCount == 0 {
                Text(NSLocalizedString("No keys for this organization.", comment: "Empty gateway inventory."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if inventory.keys.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(NSLocalizedString("No matching keys or programs", comment: "Local inventory filter is empty."), systemImage: "magnifyingglass")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(NSLocalizedString("Clear search", comment: "Clear local inventory filter.")) { searchText = "" }
                        .buttonStyle(.link)
                }
            } else if scrollsInternally {
                ScrollView { keyList(inventory) }
                    .frame(minHeight: 100, idealHeight: 240, maxHeight: 340)
            } else {
                keyList(inventory)
            }
        }
        .onChange(of: searchText) {
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                expandedKeys.formUnion(inventory.keys.map(\.id))
            }
        }
        .onChange(of: customer.sourceKeyId) {
            // A different lookup within the same organization should reveal
            // its source key, even if the previous inventory was filtered.
            searchText = ""
            if let sourceKey = customer.sourceKeyId { expandedKeys.insert(sourceKey) }
        }
    }

    private var organization: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(customer.company.name)
                .font(.callout.weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent(
                NSLocalizedString("Organization code", comment: "Gateway organization display code."),
                value: customer.company.formattedCode
            )
            .font(.caption)
            .textSelection(.enabled)
            if let phones = customer.company.phones, !phones.isEmpty {
                Label(phones.joined(separator: ", "), systemImage: "phone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
    }

    private func keyList(_ inventory: CRMInventoryPresentation) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(inventory.keys) { item in
                CRMInventoryKeyView(
                    item: item,
                    isExpanded: Binding(
                        get: { expandedKeys.contains(item.id) },
                        set: { if $0 { expandedKeys.insert(item.id) } else { expandedKeys.remove(item.id) } }
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, scrollsInternally ? 6 : 0)
    }

    private func allExpanded(_ inventory: CRMInventoryPresentation) -> Bool {
        inventory.keys.allSatisfy { expandedKeys.contains($0.id) }
    }

    private func summary(_ inventory: CRMInventoryPresentation) -> String {
        if inventory.isFiltered {
            return String(format: NSLocalizedString("%ld of %ld keys · %ld programs", comment: "Filtered inventory group counts."),
                          inventory.visibleKeyCount, inventory.totalKeyCount, inventory.visibleProgramGroupCount)
        }
        return String(format: NSLocalizedString("%ld keys · %ld programs · %ld records", comment: "Inventory counts across all keys."),
                      inventory.totalKeyCount, inventory.totalProgramGroupCount, inventory.totalRecordCount)
    }
}

private struct CRMInventoryKeyView: View {
    let item: CRMInventoryPresentation.Key
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(format: NSLocalizedString("%ld programs · %ld records", comment: "Per-key group and version record counts."),
                                item.groups.count, item.recordCount))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Link(NSLocalizedString("Personal account", comment: "Open gateway-provided key page."), destination: item.key.url)
                }
                .font(.caption)
                if item.groups.isEmpty {
                    Text(NSLocalizedString("No programs on this key.", comment: "Gateway key without records."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(item.groups) { group in CRMInventoryProgramGroupView(group: group) }
            }
            .padding(.top, 8)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(item.id))
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .textSelection(.enabled)
                Text(item.key.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if item.isSourceKey {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .help(NSLocalizedString("Key used for this lookup", comment: "Source key indicator, not license status."))
                        .accessibilityLabel(NSLocalizedString("Key used for this lookup", comment: "Source key indicator."))
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("crm.inventory.key.\(item.id)")
    }
}

private struct CRMInventoryProgramGroupView: View {
    let group: CRMInventoryPresentation.ProgramGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let firstRecord = group.records.first {
                Link(group.name.isEmpty ? NSLocalizedString("Unnamed program", comment: "Missing gateway program title.") : group.name,
                     destination: firstRecord.keyUrl)
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(NSLocalizedString("Version", comment: "Inventory version column."))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(NSLocalizedString("Release", comment: "Inventory release column."))
                    .frame(width: 92, alignment: .leading)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            ForEach(group.records) { record in
                HStack(alignment: .firstTextBaseline) {
                    Text(display(record.version))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(display(record.release))
                        .frame(width: 92, alignment: .leading)
                }
                .font(.caption.monospacedDigit())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func display(_ value: String?) -> String {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "—" : value
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(customer.company.name).font(.headline).textSelection(.enabled)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(customer.company.formattedCode).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let phones = customer.company.phones, !phones.isEmpty {
                Text(phones.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            }
            HStack {
                TextField(NSLocalizedString("Search keys, programs or versions", comment: "Global inventory search."), text: $searchText)
                    .textFieldStyle(.roundedBorder).focused($searchFocused)
                    .accessibilityIdentifier("crm.inventory.search")
                Button { searchFocused = true } label: { Image(systemName: "magnifyingglass") }
                    .keyboardShortcut("f", modifiers: .command)
                    .help(NSLocalizedString("Search keys, programs or versions", comment: "Global inventory search."))
                    .accessibilityLabel(NSLocalizedString("Search keys, programs or versions", comment: "Global inventory search."))
                if !searchText.isEmpty {
                    Button(NSLocalizedString("Clear search", comment: "Clear inventory search.")) { searchText = "" }
                }
                Text(String(format: NSLocalizedString("%ld keys · %ld programs · %ld records", comment: "Inventory counts."),
                            inventory.visibleKeyCount, inventory.visibleProgramGroupCount, inventory.visibleRecordCount))
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("crm.inventory.counts")
            }
            .controlSize(.small)
            HSplitView {
                List(selection: $selectedKey) {
                    Text(NSLocalizedString("All keys", comment: "Show programs across every key."))
                        .tag(0).accessibilityIdentifier("crm.inventory.allKeys")
                    ForEach(inventory.keys) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(item.id)).monospacedDigit()
                            Text(item.key.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .tag(item.id)
                        .accessibilityIdentifier("crm.inventory.key.\(item.id)")
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 140, idealWidth: 190, maxWidth: 280)
                VStack(alignment: .leading, spacing: 6) {
                    if let key = inventory.keys.first(where: { $0.id == keyID }) {
                        HStack {
                            Text(key.key.name).font(.callout.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Link(NSLocalizedString("Personal account", comment: "Open key portal."), destination: key.key.url)
                        }.padding(.horizontal, 8)
                    }
                    GeometryReader { geometry in
                        // Size from the detail pane, including sidebar resizing.
                        // A native Table retains ideal column widths and clips its
                        // trailing columns when squeezed. Reflow complete records
                        // rather than hiding version/release or requiring scrolling.
                        if geometry.size.width >= 620 {
                            programTable(rows)
                        } else {
                            compactPrograms(rows)
                        }
                    }
                    .copyable(rows.filter { selectedRows.contains($0.id) }.map { row in
                        [String(row.key.id), row.program.name, display(row.program.version), display(row.program.release)].joined(separator: "\t")
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
        }
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
            TableColumn(NSLocalizedString("Key number", comment: "Inventory key column.")) { row in
                Link(String(row.key.id), destination: row.key.url).monospacedDigit()
            }.width(min: 65, ideal: 80)
            TableColumn(NSLocalizedString("Program", comment: "Inventory program column.")) { row in
                Link(row.program.name.isEmpty ? NSLocalizedString("Unnamed program", comment: "Unnamed program.") : row.program.name,
                     destination: row.program.keyUrl)
                    .help(row.program.name)
            }.width(min: 140, ideal: 300)
            TableColumn(NSLocalizedString("Version", comment: "Inventory version column.")) { row in
                Text(display(row.program.version)).monospacedDigit().textSelection(.enabled)
            }.width(min: 65, ideal: 85)
            TableColumn(NSLocalizedString("Release", comment: "Inventory release column.")) { row in
                Text(display(row.program.release)).monospacedDigit().textSelection(.enabled)
            }.width(min: 65, ideal: 85)
        }
    }

    private func compactPrograms(_ rows: [CRMInventoryPresentation.Row]) -> some View {
        List(rows, selection: $selectedRows) { row in
            VStack(alignment: .leading, spacing: 5) {
                Link(row.program.name.isEmpty ? NSLocalizedString("Unnamed program", comment: "Unnamed program.") : row.program.name,
                     destination: row.program.keyUrl)
                    .lineLimit(2)
                    .help(row.program.name)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Key number", comment: "Inventory key column."))
                            .foregroundStyle(.secondary)
                        Link(String(row.key.id), destination: row.key.url).monospacedDigit()
                    }
                    compactValue(NSLocalizedString("Version", comment: "Inventory version column."), value: row.program.version)
                    compactValue(NSLocalizedString("Release", comment: "Inventory release column."), value: row.program.release)
                }
                .font(.caption)
            }
            .padding(.vertical, 3)
            .tag(row.id)
        }
        .listStyle(.inset)
        .accessibilityIdentifier("crm.inventory.compactPrograms")
    }

    private func compactValue(_ title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.secondary)
            Text(display(value)).monospacedDigit().textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func display(_ value: String?) -> String {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "—" : text
    }
}
