//
//  CRMHistoryLookupView.swift
//  Telephone
//

import SwiftUI

struct CRMHistoryLookupView: View {
    @Bindable var model: CRMHistoryLookupModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("CRM check for this call", comment: "Call history CRM sheet title."))
                    .font(.headline)
                Spacer()
                Button(NSLocalizedString("Check CRM now", comment: "Explicit fresh call-history CRM lookup.")) {
                    model.checkNow()
                }
                .disabled(!model.canCheck)
                .accessibilityIdentifier("history.crm.checkNow")
            }

            if let phone = model.callerPhone {
                Text(phone)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            Text(NSLocalizedString(
                "This check shows CRM data at the time of verification, not at the time of the call.",
                comment: "Historical call CRM check temporal scope."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            manualSearch
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    progress
                    localStatus

                    if let snapshot = model.snapshot {
                        Text(String(
                            format: NSLocalizedString("Checked: %@", comment: "Saved CRM check local timestamp."),
                            snapshot.checkedAt.formatted(date: .abbreviated, time: .standard)
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        lookupIdentity(snapshot)
                        snapshotContent(snapshot)
                    } else if !model.isLoading && !model.isChecking && model.localError == nil {
                        Text(NSLocalizedString("This call has no saved CRM check.", comment: "Call history has no previous CRM verification."))
                            .foregroundStyle(.secondary)
                    }

                    if !model.settings.enabled {
                        Text(CRMGatewayError.disabled.crmMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .frame(minHeight: 160, idealHeight: 320)

            Divider()

            HStack {
                Spacer()
                Button(NSLocalizedString("Close", comment: "Close history CRM verification sheet.")) {
                    model.close()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(minWidth: 500, idealWidth: 560, maxWidth: 720,
               minHeight: 420, idealHeight: 560, maxHeight: 760, alignment: .topLeading)
        .onDisappear { model.close() }
    }

    private var manualSearch: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(NSLocalizedString("Find an organization manually", comment: "History CRM manual fallback heading."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.callerPhone != nil {
                    Button(NSLocalizedString("Find by phone", comment: "History CRM reset to actual call phone.")) { model.searchCallerPhone() }
                        .disabled(!model.canCheck)
                }
            }
            HStack {
                TextField(NSLocalizedString("Key number", comment: "History CRM key input."), text: $model.keyNumber)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isSaving)
                    .onSubmit { if model.canSearchKey { model.searchKey() } }
                Button(NSLocalizedString("Find by key", comment: "History CRM key lookup.")) { model.searchKey() }
                    .disabled(!model.canSearchKey)
            }
            HStack {
                TextField(NSLocalizedString("Email address", comment: "History CRM email input."), text: $model.email)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isSaving)
                    .onSubmit { if model.canSearchEmail { model.searchEmail() } }
                Button(NSLocalizedString("Find by email", comment: "History CRM email lookup.")) { model.searchEmail() }
                    .disabled(!model.canSearchEmail)
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func lookupIdentity(_ snapshot: CRMHistorySnapshot) -> some View {
        switch snapshot.lookupIdentity {
        case .phone(let phone):
            Text(String(format: NSLocalizedString("Lookup by phone: %@", comment: "CRM saved lookup provenance."), phone))
                .font(.caption).foregroundStyle(.secondary)
        case .key(let number):
            Text(String(format: NSLocalizedString("Lookup by key: %@", comment: "CRM saved lookup provenance."), String(number)))
                .font(.caption).foregroundStyle(.secondary)
        case .email(let email):
            Text(String(format: NSLocalizedString("Lookup by email: %@", comment: "CRM saved lookup provenance."), email))
                .font(.caption).foregroundStyle(.secondary)
        case nil: EmptyView()
        }
    }

    @ViewBuilder
    private var progress: some View {
        if model.isLoading || model.isChecking || model.isSaving {
            HStack {
                ProgressView().controlSize(.small)
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isChecking {
                    Button(NSLocalizedString("Cancel", comment: "Cancel history CRM request.")) { model.cancelCheck() }
                        .controlSize(.small)
                }
            }
        }
    }

    private var progressText: String {
        if model.isLoading {
            return NSLocalizedString("Loading saved CRM check…", comment: "History CRM snapshot loading.")
        }
        if model.isSaving {
            return NSLocalizedString("Saving CRM check locally…", comment: "History CRM snapshot saving.")
        }
        return NSLocalizedString("Checking CRM…", comment: "History CRM fresh lookup progress.")
    }

    @ViewBuilder
    private var localStatus: some View {
        if let error = model.localError {
            Label(error.historyCRMMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("history.crm.storageError")
        }
    }

    @ViewBuilder
    private func snapshotContent(_ snapshot: CRMHistorySnapshot) -> some View {
        switch snapshot.status {
        case .matched:
            if let customer = snapshot.customer { CRMHistoryCustomerDetails(customer: customer) }
        case .notFound:
            Text(NSLocalizedString("No organization matched this lookup. Try a key number or email.", comment: "History CRM no exact match."))
                .foregroundStyle(.secondary)
        case .ambiguous:
            Text(NSLocalizedString("Several organizations match. Choose one.", comment: "History CRM ambiguous match choice."))
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.matches) { match in
                    Button { model.chooseCompany(match) } label: {
                        Text("\(match.name) · \(match.formattedCode)")
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.link)
                    .disabled(!model.canCheck)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .failed:
            if let error = snapshot.errorCode {
                Label(error.crmMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CRMHistoryCustomerDetails: View {
    let customer: CRMKeyLookupCustomer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(customer.company.name)
                .font(.callout.weight(.semibold))
                .textSelection(.enabled)
            LabeledContent(
                NSLocalizedString("Organization code", comment: "History CRM organization code."),
                value: customer.company.formattedCode
            )
            .font(.caption)
            .textSelection(.enabled)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(customer.keys) { key in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) {
                            Link(
                                NSLocalizedString("Open key in personal account", comment: "History CRM key portal link."),
                                destination: key.url
                            )
                            if key.programs.isEmpty {
                                Text(NSLocalizedString("No programs on this key.", comment: "History CRM key has no programs."))
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(key.programs) { program in
                                VStack(alignment: .leading, spacing: 2) {
                                    Link(programTitle(program), destination: program.keyUrl)
                                    if program.version != nil || program.release != nil {
                                        Text(String(
                                            format: NSLocalizedString("Version: %@ · Release: %@", comment: "History CRM program version and release."),
                                            program.version ?? "—", program.release ?? "—"
                                        ))
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .font(.caption)
                        .padding(.top, 4)
                    } label: {
                        Text("\(key.id) · \(key.name)")
                            .font(.caption.weight(.medium))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func programTitle(_ program: CRMKeyLookupProgram) -> String {
        program.name.isEmpty
            ? NSLocalizedString("Unnamed program", comment: "History CRM missing program name.")
            : program.name
    }
}

private extension CRMHistoryLocalError {
    var historyCRMMessage: String {
        switch self {
        case .loadFailed:
            NSLocalizedString("Couldn’t read this call or its saved CRM check from local history.", comment: "History CRM local read failure.")
        case .invalidSavedSnapshot:
            NSLocalizedString("The saved CRM check is invalid. Check CRM again to replace it.", comment: "History CRM corrupt snapshot.")
        case .saveFailed:
            NSLocalizedString("Couldn’t save the CRM check locally. The displayed result has not been stored.", comment: "History CRM local write failure.")
        case .recordRemoved:
            NSLocalizedString("This call was removed from history. Its CRM check was not saved.", comment: "History CRM deleted call cannot be saved.")
        }
    }
}
