//
//  CRMKeyLookupView.swift
//  Telephone
//

import SwiftUI

struct CRMKeyLookupView: View {
    @Bindable var model: CRMKeyLookupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("CRM lookup by key", comment: "Manual CRM lookup section title."))
                .font(.caption.weight(.semibold))
            HStack {
                TextField(
                    NSLocalizedString("Key number", comment: "CRM numeric key input."),
                    text: $model.keyNumber
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("customer.crm.keyNumber")
                .onSubmit { if model.canSearch { model.search() } }
                Button(NSLocalizedString("Search", comment: "CRM search button.")) { model.search() }
                    .disabled(!model.canSearch)
                    .accessibilityIdentifier("customer.crm.search")
            }
            .controlSize(.small)

            lookupContent
        }
        .onChange(of: model.settings.generation) { model.settingsDidChange() }
        .onDisappear { model.cancel() }
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
            Text(NSLocalizedString("No owner found for this key.", comment: "CRM key not found state."))
                .font(.caption)
                .foregroundStyle(.secondary)
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
