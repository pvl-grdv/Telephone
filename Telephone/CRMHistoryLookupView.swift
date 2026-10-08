//
//  CRMHistoryLookupView.swift
//  Telephone
//

import SwiftUI
import AppKit

struct CRMHistoryLookupView: View {
    @Bindable var model: CRMHistoryLookupModel
    var onClose: () -> Void = {}
    @State private var searchKind = SearchKind.key
    @FocusState private var lookupFocused: Bool

    private enum SearchKind: String, CaseIterable {
        case key, email
        var title: String {
            NSLocalizedString(self == .key ? "Key number" : "Email address", comment: "Manual CRM search kind.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let phone = model.callerPhone {
                    Label(phone, systemImage: "phone").textSelection(.enabled)
                }
                Spacer()
                Button(NSLocalizedString("Refresh lookup", comment: "Repeat the displayed lookup, preserving its query and selected organization.")) {
                    model.checkNow()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.canCheck)
                .accessibilityIdentifier("history.crm.checkNow")
                Button(NSLocalizedString("Close", comment: "Close CRM window."), action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            manualSearch
            progress
            localStatus
            if let snapshot = model.snapshot {
                HStack {
                    Text(String(format: NSLocalizedString(
                        model.isChecking ? "Previous result: %@" : "Checked: %@", comment: "Result time, separate from current request."),
                        snapshot.checkedAt.formatted(date: .abbreviated, time: .standard)))
                    lookupIdentity(snapshot)
                }
                .font(.caption).foregroundStyle(.secondary)
                snapshotContent(snapshot)
                phoneLinkContent
            } else if !model.isLoading && !model.isChecking && model.localError == nil {
                Text(NSLocalizedString("This call has no saved CRM check.", comment: "No saved CRM data."))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Spacer()
            }
            if !model.settings.enabled {
                Text(CRMGatewayError.disabled.crmMessage).font(.caption).foregroundStyle(.secondary)
            }
            Text(NSLocalizedString("This check shows CRM data at the time of verification, not at the time of the call.", comment: "CRM temporal scope."))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(minWidth: 660, maxWidth: .infinity, minHeight: 440, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            NSLocalizedString("Link phone to organization", comment: "Confirm CRM history phone append."),
            isPresented: Binding(
                get: { model.pendingPhoneLink != nil },
                set: { if !$0 { model.dismissPhoneLinkConfirmation() } }
            ),
            titleVisibility: .visible,
            presenting: model.pendingPhoneLink
        ) { confirmation in
            Button(NSLocalizedString("Link phone", comment: "Confirm phone append for an existing call.")) {
                model.confirmPhoneLink(confirmation)
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel CRM history phone append."), role: .cancel) {
                model.dismissPhoneLinkConfirmation()
            }
        } message: { confirmation in
            Text(String(format: NSLocalizedString(
                "Add the phone from this call, %@, to %@? Existing phone numbers will be preserved.",
                comment: "History call phone association, names exact phone and organization."
            ), confirmation.phone, confirmation.companyName))
        }
        .onDisappear { model.close() }
    }

    private var manualSearch: some View {
        HStack(spacing: 8) {
            Picker(NSLocalizedString("Search by", comment: "Manual CRM lookup kind."), selection: $searchKind) {
                ForEach(SearchKind.allCases, id: \.self) { kind in Text(kind.title).tag(kind) }
            }
            .labelsHidden().frame(width: 120)
            TextField(searchKind.title, text: searchKind == .key ? $model.keyNumber : $model.email)
                .textFieldStyle(.roundedBorder).focused($lookupFocused)
                .onSubmit { submitSearch() }
                .accessibilityIdentifier("history.crm.query")
            Button(NSLocalizedString("Find", comment: "Run manual CRM lookup.")) { submitSearch() }
                .disabled(searchKind == .key ? !model.canSearchKey : !model.canSearchEmail)
            if model.callerPhone != nil {
                Button(NSLocalizedString("Find by call number", comment: "Reset lookup to actual caller, distinct from refresh.")) {
                    model.searchCallerPhone()
                }
                .disabled(!model.canCheck)
                .accessibilityIdentifier("history.crm.callerLookup")
            }
        }
        .controlSize(.small)
        .disabled(model.isSaving || model.phoneLinkState == .saving || model.phoneLinkState == .refreshing)
        .onChange(of: searchKind) { lookupFocused = true }
        .onChange(of: model.snapshot?.lookupIdentity) {
            if case .email = model.snapshot?.lookupIdentity { searchKind = .email }
            else if case .key = model.snapshot?.lookupIdentity { searchKind = .key }
        }
    }

    private func submitSearch() {
        if searchKind == .key { model.searchKey() } else { model.searchEmail() }
    }

    @ViewBuilder
    private var phoneLinkContent: some View {
        if model.canLinkPhone {
            if needsPhoneLinkRefresh {
                Button(NSLocalizedString("Refresh organization", comment: "Fresh key lookup required before retrying CRM append.")) {
                    model.preparePhoneLink()
                }
                .controlSize(.small)
            } else {
                Button(NSLocalizedString("Link number to organization", comment: "Start explicit CRM history phone association.")) {
                    model.preparePhoneLink()
                }
                .controlSize(.small)
                .accessibilityIdentifier("history.crm.linkPhone")
            }
            Text(NSLocalizedString(
                "A fresh key lookup runs before confirmation.",
                comment: "CRM history append requires a current key result."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if model.isCallerLinkedToKey, model.phoneLinkState == .idle {
            Text(NSLocalizedString("This number is already linked to the organization.", comment: "History key already contains caller phone."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        switch model.phoneLinkState {
        case .idle:
            EmptyView()
        case .refreshing:
            HStack {
                ProgressView().controlSize(.small)
                Text(NSLocalizedString("Refreshing key before phone confirmation…", comment: "History CRM current key lookup progress."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .saving:
            HStack {
                ProgressView().controlSize(.small)
                Text(NSLocalizedString("Linking number…", comment: "History CRM append progress."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .saved(let added):
            Label(
                added
                    ? NSLocalizedString("Number linked to organization", comment: "History CRM append succeeded.")
                    : NSLocalizedString("This number is already linked to the organization.", comment: "History CRM append already present."),
                systemImage: "checkmark.circle"
            )
            .font(.caption)
        case .failed(let error):
            Label(error.crmMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var needsPhoneLinkRefresh: Bool {
        if case .failed = model.phoneLinkState { return true }
        return false
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
            if let customer = snapshot.customer {
                CRMCustomerInventoryView(customer: customer, usesBrowserLayout: true)
                    .id(customer.company.id)
            }
        case .notFound:
            Text(NSLocalizedString("No organization matched this lookup. Try a key number or email.", comment: "History CRM no exact match."))
                .foregroundStyle(.secondary)
        case .ambiguous:
            Text(NSLocalizedString("Several organizations match. Choose one.", comment: "History CRM ambiguous match choice."))
                .font(.callout)
                .foregroundStyle(.secondary)
            List {
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
            if !model.isChecking, let error = snapshot.errorCode {
                Label(error.crmMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
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
        case .callerChanged:
            NSLocalizedString("The phone stored for this call changed. Reopen its CRM check before linking.", comment: "History CRM caller changed before append.")
        }
    }
}


/// A resizable auxiliary window: opening CRM never blocks the call-history window.
@MainActor
final class CRMHistoryWindowController: NSWindowController, NSWindowDelegate {
    private let model: CRMHistoryLookupModel
    private let didClose: () -> Void

    init(model: CRMHistoryLookupModel, didClose: @escaping () -> Void) {
        self.model = model
        self.didClose = didClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = NSLocalizedString("CRM check for this call", comment: "CRM auxiliary window title.")
        window.contentMinSize = NSSize(width: 660, height: 440)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: CRMHistoryLookupView(model: model) { [weak self] in self?.close() })
        window.center()
        window.setFrameAutosaveName("Telephone.CRMHistory")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func windowWillClose(_ notification: Notification) {
        model.close()
        didClose()
    }
}
