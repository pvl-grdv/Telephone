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

    var example: String {
        switch self {
        case .key: "12345"
        case .email: "name@example.com"
        case .organizationCode: "12-34-5678"
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

    var validationIdentifier: String {
        fieldIdentifier + ".validation"
    }
}

struct CRMManualSearchView: View {
    @Bindable var model: CRMKeyLookupModel
    @FocusState private var focusedSearch: CRMManualSearchKind?
    @State private var visitedFields: Set<CRMManualSearchKind> = []
    var dismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Search organization", comment: "Manual CRM lookup heading."))
                .font(.headline)

            // No search method is prioritized. Each uses the same control sizing,
            // validation and keyboard behavior in the CRM window and call popover.
            VStack(alignment: .leading, spacing: 10) {
                ForEach(CRMManualSearchKind.allCases, id: \.self) { kind in
                    searchRow(for: kind)
                }
            }
            .controlSize(.regular)
        }
        .padding(14)
        .frame(width: 500)
        .onChange(of: focusedSearch) { oldValue, newValue in
            if let oldValue, oldValue != newValue {
                visitedFields.insert(oldValue)
            }
        }
    }

    private func searchRow(for kind: CRMManualSearchKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(kind.title)
                    .frame(width: 155, alignment: .leading)

                TextField(kind.example, text: manualQuery(for: kind))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedSearch, equals: kind)
                    .accessibilityLabel(Text(kind.title))
                    .accessibilityIdentifier(kind.fieldIdentifier)
                    .disabled(model.phoneLinkState == .saving)
                    .onSubmit { runManualSearch(for: kind) }

                Button(NSLocalizedString("Find", comment: "Run manual CRM lookup.")) {
                    runManualSearch(for: kind)
                }
                .frame(width: 70)
                .disabled(!canRunManualSearch(for: kind))
                .accessibilityLabel(Text(
                    NSLocalizedString("Find", comment: "Run manual CRM lookup.") + ": " + kind.title
                ))
                .accessibilityIdentifier(kind.actionIdentifier)
            }

            // Show errors after leaving a field or attempting Return. This
            // avoids displaying an error on every intermediate keystroke.
            if visitedFields.contains(kind), let message = validationMessage(for: kind) {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 165)
                    .accessibilityIdentifier(kind.validationIdentifier)
            }
        }
    }

    private func manualQuery(for kind: CRMManualSearchKind) -> Binding<String> {
        switch kind {
        case .key: $model.keyNumber
        case .email: $model.email
        case .organizationCode: $model.organizationCode
        }
    }

    private func validationMessage(for kind: CRMManualSearchKind) -> String? {
        let value = manualQuery(for: kind).wrappedValue
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        switch kind {
        case .key:
            return CRMKeyNumber.parse(value) == nil ? CRMGatewayError.invalidKeyNumber.crmMessage : nil
        case .email:
            return CRMEmailAddress.normalize(value) == nil ? CRMGatewayError.invalidEmail.crmMessage : nil
        case .organizationCode:
            return CRMOrganizationCode.normalize(value) == nil ? CRMGatewayError.invalidOrganizationCode.crmMessage : nil
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
        guard canRunManualSearch(for: kind) else {
            visitedFields.insert(kind)
            return
        }
        switch kind {
        case .key: model.search()
        case .email: model.searchEmail()
        case .organizationCode: model.searchOrganizationCode()
        }
        dismiss?()
    }
}
