//
//  CRMManualSearchView.swift
//  Telephone
//
//  The live CRM browser owns the popover; this view owns only its controls.
//

import SwiftUI

enum CRMManualSearchKind: Hashable, CaseIterable {
    case key
    case email
    case organizationCode

    var title: String {
        switch self {
        case .key:
            NSLocalizedString("Key number", comment: "CRM numeric key input.")
        case .email:
            NSLocalizedString("Email address", comment: "Manual CRM email input.")
        case .organizationCode:
            NSLocalizedString("Registration number", comment: "CRM organization registration number input.")
        }
    }

    var fieldIdentifier: String {
        switch self {
        case .key: "customer.crm.keyNumber"
        case .email: "customer.crm.email"
        case .organizationCode: "customer.crm.organizationCode"
        }
    }

    var actionIdentifier: String {
        switch self {
        case .key: "customer.crm.search"
        case .email: "customer.crm.searchEmail"
        case .organizationCode: "customer.crm.searchOrganizationCode"
        }
    }
}

struct CRMManualSearchView: View {
    @Bindable var model: CRMKeyLookupModel
    @FocusState private var focusedSearch: CRMManualSearchKind?
    var dismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Search organization", comment: "Manual CRM lookup heading."))
                .font(.headline)

            // A key number can be entered directly, without first switching search mode.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(CRMManualSearchKind.allCases, id: \.self) { kind in
                    searchRow(for: kind)
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 500)
        .onAppear { focusedSearch = .key }
    }

    private func searchRow(for kind: CRMManualSearchKind) -> some View {
        HStack(spacing: 8) {
            Text(kind.title)
                .frame(width: 155, alignment: .leading)
            TextField(kind.title, text: manualQuery(for: kind))
                .textFieldStyle(.roundedBorder)
                .focused($focusedSearch, equals: kind)
                .accessibilityIdentifier(kind.fieldIdentifier)
                .disabled(model.phoneLinkState == .saving)
                .onSubmit { runManualSearch(for: kind) }

            Button(NSLocalizedString("Find", comment: "Run manual CRM lookup.")) {
                runManualSearch(for: kind)
            }
            .disabled(!canRunManualSearch(for: kind))
            .accessibilityIdentifier(kind.actionIdentifier)
        }
    }

    private func manualQuery(for kind: CRMManualSearchKind) -> Binding<String> {
        switch kind {
        case .key: $model.keyNumber
        case .email: $model.email
        case .organizationCode: $model.organizationCode
        }
    }

    private func canRunManualSearch(for kind: CRMManualSearchKind) -> Bool {
        switch kind {
        case .key: model.canSearch
        case .email: model.canSearchEmail
        case .organizationCode: model.canSearchOrganizationCode
        }
    }

    private func runManualSearch(for kind: CRMManualSearchKind) {
        guard canRunManualSearch(for: kind) else { return }
        switch kind {
        case .key: model.search()
        case .email: model.searchEmail()
        case .organizationCode: model.searchOrganizationCode()
        }
        dismiss?()
    }
}
