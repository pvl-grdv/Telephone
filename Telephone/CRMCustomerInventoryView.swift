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
    @State private var searchText = ""
    @State private var expandedKeys: Set<Int>

    init(customer: CRMKeyLookupCustomer, scrollsInternally: Bool = false) {
        self.customer = customer
        self.scrollsInternally = scrollsInternally
        let firstKey = customer.sourceKeyId ?? customer.keys.map(\.id).min()
        _expandedKeys = State(initialValue: Set(firstKey.map { [$0] } ?? []))
    }

    var body: some View {
        let inventory = CRMInventoryPresentation(customer: customer, searchText: searchText)
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
