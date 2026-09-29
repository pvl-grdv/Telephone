//
//  CRMKeyLookupView.swift
//  Telephone
//

import SwiftUI

struct CRMKeyLookupView: View {
    @Bindable var model: CRMKeyLookupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString("CRM", comment: "CRM lookup section title."))
                    .font(.caption.weight(.semibold))
                if let phone = model.callerPhone {
                    Text(phone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    Button(NSLocalizedString("Find by phone", comment: "Retry caller phone CRM lookup.")) {
                        model.searchCallerPhone()
                    }
                    .controlSize(.small)
                    .disabled(model.state == .loading || model.phoneLinkState == .saving)
                }
            }
            HStack {
                TextField(
                    NSLocalizedString("Key number", comment: "CRM numeric key input."),
                    text: $model.keyNumber
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("customer.crm.keyNumber")
                .disabled(model.phoneLinkState == .saving)
                .onSubmit { if model.canSearch { model.search() } }
                Button(NSLocalizedString("Search", comment: "CRM search button.")) { model.search() }
                    .disabled(!model.canSearch)
                    .accessibilityIdentifier("customer.crm.search")
            }
            .controlSize(.small)

            lookupContent
            phoneLinkContent
        }
        .onChange(of: model.settings.generation) { model.settingsDidChange() }
        .onAppear { model.activateContext() }
        .onDisappear { model.deactivateContext() }
        .confirmationDialog(
            NSLocalizedString("Link phone to organization", comment: "CRM phone linking confirmation title."),
            isPresented: Binding(
                get: { model.pendingPhoneLink != nil },
                set: { if !$0 { model.pendingPhoneLink = nil } }
            ),
            titleVisibility: .visible,
            presenting: model.pendingPhoneLink
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
            Text(NSLocalizedString("No organization found. Search by key number.", comment: "CRM no exact phone or key match."))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .choosing(let matches):
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("This number belongs to several organizations. Choose one.", comment: "Ambiguous CRM phone matches."))
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
        case .failed(let error):
            Label(error.crmMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loaded(let response):
            if let customer = response.data {
                customerDetails(customer)
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
        case .saving:
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

    private func customerDetails(_ customer: CRMKeyLookupCustomer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(customer.company.name)
                .font(.callout.weight(.semibold))
                .textSelection(.enabled)
            LabeledContent(
                NSLocalizedString("Organization code", comment: "CRM organization code label."),
                value: customer.company.formattedCode
            )
            .font(.caption)
            .textSelection(.enabled)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(customer.keys) { key in
                        CRMKeyLookupKeyView(key: key)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
            }
            .frame(minHeight: 100, idealHeight: 210, maxHeight: 260)
        }
    }
}

private struct CRMKeyLookupKeyView: View {
    let key: CRMKeyLookupKey

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Link(
                    NSLocalizedString("Open key in personal account", comment: "CRM key portal action."),
                    destination: key.url
                )
                if key.programs.isEmpty {
                    Text(NSLocalizedString("No programs on this key.", comment: "CRM key without programs."))
                        .foregroundStyle(.secondary)
                }
                ForEach(key.programs) { program in
                    VStack(alignment: .leading, spacing: 2) {
                        Link(programTitle(program), destination: program.keyUrl)
                        if program.version != nil || program.release != nil {
                            Text(String(
                                format: NSLocalizedString(
                                    "Version: %@ · Release: %@",
                                    comment: "CRM program version and release."
                                ),
                                program.version ?? "—",
                                program.release ?? "—"
                            ))
                            .foregroundStyle(.secondary)
                        }
                    }
                    .textSelection(.enabled)
                }
            }
            .font(.caption)
            .padding(.top, 4)
        } label: {
            Text("\(key.id) · \(key.name)")
                .font(.caption.weight(.medium))
                .textSelection(.enabled)
        }
    }

    private func programTitle(_ program: CRMKeyLookupProgram) -> String {
        let name = program.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty
            ? NSLocalizedString("Unnamed program", comment: "CRM missing program title.")
            : name
    }
}
