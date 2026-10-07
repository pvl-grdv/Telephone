import Foundation

@MainActor
final class CustomerContextCoordinator {
    private weak var callController: CallController?
    private let model: CallWindowModel
    private let store: any CustomerContextStoring
    private let pendingWrites: CustomerContextPendingWrites

    private var loadTask: Task<Void, Never>?
    private var saveDebounceTask: Task<Void, Never>?
    private var saveTail: Task<Void, Never>?
    private var saveGeneration = 0
    private var loadedKey: String?
    private var loadedAddress: CustomerPartyAddress?
    private var loadedDisplayName = ""
    private var loadedAccountUUID: String?
    private var loadedCallIdentifier: String?
    private var baseline: CustomerContextSnapshot?
    private var saveSession: CustomerContextSaveSession?
    private var isApplyingSnapshot = false

    init(callController: CallController, model: CallWindowModel, store: any CustomerContextStoring = DefaultCustomerContextStorage(), pendingWrites: CustomerContextPendingWrites = CustomerContextPendingWrites()) {
        self.callController = callController
        self.model = model
        self.store = store
        self.pendingWrites = pendingWrites
    }

    func loadIfNeeded() {
        guard isEnabled, let callController, let address = partyAddress,
              let accountUUID = callController.customerContextAccountUUID,
              let contextIdentifier = callController.call?.historyIdentifier else { return }
        let key = "\(address.kind)|\(address.normalizedValue)|\(accountUUID)|\(contextIdentifier)"
        guard loadedKey != key else { return }
        loadTask?.cancel()
        loadedKey = key
        loadedAddress = address
        loadedAccountUUID = accountUUID
        loadedCallIdentifier = contextIdentifier
        let displayName = customerDisplayName
        loadedDisplayName = displayName
        baseline = nil
        model.customerContextLoaded = false
        model.customerContextLoadFailed = false
        model.customerContextSaveSucceeded = false
        model.customerContextSaveConflict = false

        let pendingSave = saveTail
        loadTask = Task { [weak self, store] in
            if let pendingSave { await pendingSave.value }
            guard !Task.isCancelled else { return }
            let result = await store.load(address: address, displayName: displayName, accountUUID: accountUUID, callIdentifier: contextIdentifier)
            guard !Task.isCancelled, let self, self.loadedKey == key else { return }
            switch result {
            case .success(let snapshot):
                self.isApplyingSnapshot = true
                self.baseline = snapshot
                self.saveSession = CustomerContextSaveSession()
                // Contact organization is a display fallback, not an edit to
                // persist when the user only changes a note.
                self.model.customerCompany = snapshot.company.isEmpty ? self.model.contactOrganization : snapshot.company
                self.model.customerKeys = snapshot.keys.joined(separator: ", ")
                self.model.customerEmails = snapshot.emails.joined(separator: ", ")
                self.model.customerNote = snapshot.currentCallNote
                self.model.previousConversationCount = snapshot.previousConversationCount
                self.model.lastCallDate = snapshot.lastCallDate
                self.model.recentCustomerNotes = snapshot.recentNotes
                self.model.customerContextLoaded = true
                self.model.customerContextLoadFailed = false
                self.isApplyingSnapshot = false
            case .failure:
                self.model.customerContextLoaded = false
                self.model.customerContextLoadFailed = true
            }
        }
    }

    func reload() {
        loadedKey = nil
        loadIfNeeded()
    }

    func callDidChange() {
        saveNow(ignoringPreference: true)
        loadTask?.cancel()
        loadTask = nil
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        loadedKey = nil
        loadedAddress = nil
        loadedDisplayName = ""
        loadedAccountUUID = nil
        loadedCallIdentifier = nil
        baseline = nil
        saveSession = nil
        resetPresentation()
    }

    func scheduleSave() {
        guard isEnabled, model.customerContextLoaded, !isApplyingSnapshot, saveSession?.conflict == nil else { return }
        model.customerContextSaveSucceeded = false
        model.customerContextSaveConflict = false
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.saveNow()
        }
    }

    func visibilityChanged(_ isVisible: Bool) {
        if isVisible {
            loadIfNeeded()
        } else {
            saveNow(ignoringPreference: true)
            loadTask?.cancel()
            loadTask = nil
            saveDebounceTask?.cancel()
            saveDebounceTask = nil
            loadedKey = nil
            model.customerContextLoaded = false
            model.customerContextLoadFailed = false
        }
    }

    func saveNow(ignoringPreference: Bool = false) {
        guard (ignoringPreference || isEnabled), model.customerContextLoaded,
              !isApplyingSnapshot, let address = loadedAddress, let contextKey = loadedKey,
              let accountUUID = loadedAccountUUID, let callIdentifier = loadedCallIdentifier,
              let baseline, let saveSession, saveSession.conflict == nil else { return }
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        let company = baseline.company.isEmpty && model.customerCompany == model.contactOrganization
            ? baseline.company : model.customerCompany
        let edit = CustomerContextEdit(baseline: baseline, company: company,
            keys: listValues(model.customerKeys), emails: listValues(model.customerEmails), note: model.customerNote)
        guard !edit.isEmpty else { return }
        let displayName = loadedDisplayName
        saveGeneration += 1
        let generation = saveGeneration
        let previousSave = saveTail
        let savedGeneration = saveSession.sequence.generation
        model.customerContextSaving = true
        model.customerContextSaveFailed = false
        model.customerContextSaveSucceeded = false
        model.customerContextSaveConflict = false

        let task = Task { [weak self, store] in
            if let previousSave { await previousSave.value }
            // Previous writes from this window advance the expected values;
            // fields untouched by this edit remain absent from the patch.
            let appliedEdit = saveSession.sequence.rebased(edit, since: savedGeneration)
            let result: CustomerContextSaveResult
            if let conflict = saveSession.conflict {
                result = .conflict(conflict)
            } else {
                result = await store.save(address: address, displayName: displayName,
                    accountUUID: accountUUID, callIdentifier: callIdentifier, edit: appliedEdit)
            }
            if case .conflict(let current) = result { saveSession.conflict = current }
            if case .success(let snapshot) = result { saveSession.sequence.record(edit: appliedEdit, saved: snapshot) }
            guard let self, self.loadedKey == contextKey else { return }
            if case .success(let snapshot) = result {
                self.mergeSavedSnapshot(snapshot, edit: edit)
                self.baseline = snapshot
            }
            guard self.saveGeneration == generation else { return }
            self.model.customerContextSaving = false
            switch result {
            case .success:
                self.model.customerContextSaveConflict = false
                self.model.customerContextSaveFailed = false
                self.model.customerContextSaveSucceeded = true
            case .conflict:
                // Preserve the user's draft. Reload is explicit; automatic
                // retry against a fresh baseline would overwrite another window.
                self.model.customerContextSaveConflict = true
                self.model.customerContextSaveFailed = true
                self.model.customerContextSaveSucceeded = false
            case .failure:
                self.model.customerContextSaveConflict = false
                self.model.customerContextSaveFailed = true
                self.model.customerContextSaveSucceeded = false
            }
        }
        saveTail = task
        pendingWrites.track(task)
    }

    private func mergeSavedSnapshot(_ snapshot: CustomerContextSnapshot, edit: CustomerContextEdit) {
        isApplyingSnapshot = true
        defer { isApplyingSnapshot = false }
        let oldCompany = edit.baseline.company.isEmpty ? model.contactOrganization : edit.baseline.company
        if model.customerCompany == (edit.company ?? oldCompany) {
            model.customerCompany = snapshot.company.isEmpty ? model.contactOrganization : snapshot.company
        }
        if listValues(model.customerKeys) == (edit.keys ?? edit.baseline.keys) {
            model.customerKeys = snapshot.keys.joined(separator: ", ")
        }
        if listValues(model.customerEmails) == (edit.emails ?? edit.baseline.emails) {
            model.customerEmails = snapshot.emails.joined(separator: ", ")
        }
        if model.customerNote == (edit.note ?? edit.baseline.currentCallNote) {
            model.customerNote = snapshot.currentCallNote
        }
    }

    func retrySave() { saveNow() }

    func flushPendingChanges() async {
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        saveNow(ignoringPreference: true)
        if let saveTail { await saveTail.value }
    }

    func invalidate() {
        saveNow(ignoringPreference: true)
        loadTask?.cancel()
        loadTask = nil
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        loadedKey = nil
        loadedAddress = nil
        model.customerContextLoaded = false
    }

    private func resetPresentation() {
        model.customerCompany = ""
        model.customerKeys = ""
        model.customerEmails = ""
        model.customerNote = ""
        model.previousConversationCount = 0
        model.lastCallDate = nil
        model.recentCustomerNotes = []
        model.customerContextLoaded = false
        model.customerContextLoadFailed = false
        model.customerContextSaving = false
        model.customerContextSaveFailed = false
        model.customerContextSaveSucceeded = false
        model.customerContextSaveConflict = false
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: UserDefaultsKeys.showCustomerContext) as? Bool ?? true
    }

    private var partyAddress: CustomerPartyAddress? {
        guard let callController else { return nil }
        if let uri = callController.call?.remoteURI ?? callController.redialURI {
            return CustomerPartyAddress(user: uri.user, host: uri.host)
        }
        let entered = callController.enteredCallDestination?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !entered.isEmpty else { return nil }
        return CustomerPartyAddress(user: entered, host: "")
    }

    private var customerDisplayName: String {
        guard let callController else { return "" }
        let addressBookName = callController.nameFromAddressBook ?? ""
        return addressBookName.isEmpty ? (callController.displayedName ?? "") : addressBookName
    }

    private func listValues(_ text: String) -> [String] {
        text.split { $0 == "," || $0 == ";" || $0.isNewline }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

// Captured saves retain their sequence independently of the window lifetime.
@MainActor
private final class CustomerContextSaveSession {
    var sequence = CustomerContextEditSequence()
    var conflict: CustomerContextSnapshot?
}
