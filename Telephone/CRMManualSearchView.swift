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
    @Binding var searchKind: CRMManualSearchKind
    var dismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Search organization", comment: "Manual CRM lookup heading."))
                .font(.headline)

            HStack(spacing: 8) {
                Picker(NSLocalizedString("Search by", comment: "CRM manual lookup kind."),
                       selection: $searchKind) {
                    ForEach(CRMManualSearchKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .accessibilityIdentifier("customer.crm.lookupKind")

                TextField(searchKind.title, text: manualQuery)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(searchKind.fieldIdentifier)
                    .disabled(model.phoneLinkState == .saving)
                    .onSubmit { runManualSearch() }

                Button(NSLocalizedString("Find", comment: "Run manual CRM lookup.")) {
                    runManualSearch()
                }
                .disabled(!canRunManualSearch)
                .accessibilityIdentifier(searchKind.actionIdentifier)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 500)
    }

    private var manualQuery: Binding<String> {
        switch searchKind {
        case .key: $model.keyNumber
        case .email: $model.email
        case .organizationCode: $model.organizationCode
        }
    }

    private var canRunManualSearch: Bool {
        switch searchKind {
        case .key: model.canSearch
        case .email: model.canSearchEmail
        case .organizationCode: model.canSearchOrganizationCode
        }
    }

    private func runManualSearch() {
        guard canRunManualSearch else { return }
        switch searchKind {
        case .key: model.search()
        case .email: model.searchEmail()
        case .organizationCode: model.searchOrganizationCode()
        }
        dismiss?()
    }
}
