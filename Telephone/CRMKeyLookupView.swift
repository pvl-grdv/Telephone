//
//  CRMKeyLookupView.swift
//  Telephone
//

import SwiftUI

struct CRMKeyLookupView: View {
    @Bindable var model: CRMKeyLookupModel
    @State private var showsManualSearch = false
    @State private var searchKind: CRMManualSearchKind = .key
    var showsInlineSearch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsInlineSearch {
                CRMManualSearchView(model: model, searchKind: $searchKind)
            } else {
                HStack(spacing: 8) {
                    if let phone = model.callerPhone {
                    Button(NSLocalizedString("Find by phone", comment: "Retry caller phone CRM lookup.")) {
                        model.searchCallerPhone()
                    }
                    .controlSize(.small)
                    .disabled(model.state == .loading || model.phoneLinkState == .saving)
                    .help(phone)
                    }

                    Spacer(minLength: 8)
                    Button(NSLocalizedString("Search organization…", comment: "Open manual CRM organization lookup.")) {
                        showsManualSearch = true
                    }
                    .controlSize(.small)
                    .popover(isPresented: $showsManualSearch, arrowEdge: .bottom) {
                        CRMManualSearchView(
                            model: model,
                            searchKind: $searchKind,
                            dismiss: { showsManualSearch = false }
                        )
                    }
                }
            }

            lookupContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            phoneLinkContent
        }
        // Closing the browser must not cancel the automatic caller lookup or
        // a dispatched phone append. Only explicit Cancel can dismiss these.
        .confirmationDialog(
            Text(NSLocalizedString("Link phone to organization", comment: "CRM phone linking confirmation title.")),
            item: $model.pendingPhoneLink,
            titleVisibility: .visible
        ) { confirmation in
            Button(NSLocalizedString("Link phone", comment: "Confirm CRM phone association.")) {
                model.confirmPhoneLink(confirmation)
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel CRM phone association."), role: .cancel) {
                model.pendingPhoneLink = nil
            }
        } message: { confirmation in
            Text(String(
                format: NSLocalizedString(
                    "Add %@ to %@? Existing phone numbers will be preserved.",
                    comment: "Explicit CRM phone append confirmation."
                ),
                confirmation.phone, confirmation.companyName
            ))
        }
    }

    @ViewBuilder
    private var lookupContent: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .loading:
            HStack {
                ProgressView().controlSize(.mini)
                Text(NSLocalizedString("Searching CRM…", comment: "CRM lookup loading status."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(NSLocalizedString("Cancel", comment: "Cancel CRM lookup.")) { model.cancel() }
                    .controlSize(.small)
            }
        case .notFound:
            Text(NSLocalizedString("No organization found. Search by key, email or registration number.", comment: "CRM no exact lookup match."))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .choosing(let matches):
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("Several organizations match. Choose one.", comment: "Ambiguous CRM phone or email matches."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(matches) { match in
                        Button { model.chooseCompany(match) } label: {
                            Text("\(match.name) · \(match.formattedCode)")
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.link)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .failed(let error):
            Label(error.crmMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loaded(let response):
            if let customer = response.data {
                CRMCustomerInventoryView(customer: customer)
                    .id(customer.company.id)
            }
        }
    }

    @ViewBuilder
    private var phoneLinkContent: some View {
        if model.canLinkPhone {
            Button(NSLocalizedString("Link number to organization", comment: "Begin CRM phone association.")) {
                model.preparePhoneLink()
            }
            .controlSize(.small)
            .accessibilityIdentifier("customer.crm.linkPhone")
        }
        switch model.phoneLinkState {
        case .idle:
            if model.isCallerAlreadyLinked {
                Text(NSLocalizedString("This number is already linked to the organization.", comment: "CRM existing phone association."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .refreshing, .saving:
            HStack {
                ProgressView().controlSize(.mini)
                Text(NSLocalizedString("Linking number…", comment: "CRM phone write progress."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .saved(let added):
            Label(
                added
                    ? NSLocalizedString("Number linked to organization", comment: "CRM phone append success.")
                    : NSLocalizedString("This number is already linked to the organization.", comment: "CRM phone append no-op."),
                systemImage: "checkmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .failed(let error):
            Label(error.crmMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(NSLocalizedString("Refresh organization", comment: "Reload current company before retrying append.")) {
                model.search()
            }
            .controlSize(.small)
        }
    }

}
