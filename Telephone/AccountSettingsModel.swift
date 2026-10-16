//
//  AccountSettingsModel.swift
//  Telephone
//

import Foundation
import Observation
import UseCases

private let accountSetupDidAddNotification = Notification.Name("AKAccountSetupControllerDidAddAccount")
private let maximumAccountCount = 32

// The identity and password describe the same Keychain item.
private struct LoadedAccountCredentials: Equatable {
    var service = ""
    var account = ""
    var password = ""
}

@MainActor
@Observable
final class AccountSettingsModel {
    var accounts: [AccountSettingsSummary] = []

    var selection: String? {
        willSet {
            if newValue != selection {
                persistSelectedDraftNow()
            }
        }
        didSet {
            if oldValue != selection {
                loadSelectedDraft()
            }
        }
    }

    var draft = AccountSettingsDraft() {
        didSet {
            draftDidChange(from: oldValue)
        }
    }

    var passwordIsLoading = false
    var credentialsAreSaving = false
    var showsCredentialsError = false
    var pendingRemovalID: String?

    var presentAddAccount: (() -> Void)?

    @ObservationIgnored
    private weak var preferencesController: AnyObject?

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private let credentials: any CredentialsStoring

    @ObservationIgnored
    private var passwordLoadTask: Task<Void, Never>?

    @ObservationIgnored
    private var autosaveTask: Task<Void, Never>?

    @ObservationIgnored
    private var isApplyingDraft = false

    @ObservationIgnored
    private var hasUnsavedDraft = false

    @ObservationIgnored
    private var credentialsAreDirty = false

    @ObservationIgnored
    private var loadedCredentials = LoadedAccountCredentials()

    @ObservationIgnored
    private var accountAddedObservation: NotificationObservation?

    init(
        preferencesController: AnyObject?,
        defaults: UserDefaults = .standard,
        credentials: any CredentialsStoring,
        notificationCenter: NotificationCenter = .default
    ) {
        self.preferencesController = preferencesController
        self.defaults = defaults
        self.credentials = credentials

        accountAddedObservation = NotificationObservation(
            center: notificationCenter,
            name: accountSetupDidAddNotification
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.accountDidAdd()
            }
        }
        reload()
    }

    var hasSelection: Bool {
        selection != nil
    }

    var canAddAccount: Bool {
        accounts.count < maximumAccountCount
    }

    var accountListInteractionDisabled: Bool {
        passwordIsLoading || credentialsAreSaving
    }

    var selectedAccountTitle: String {
        guard let selection else { return "" }
        return accounts.first(where: { $0.id == selection })?.title ?? ""
    }

    var removalAlertTitle: String {
        String(
            format: NSLocalizedString(
                "Delete “%@”?",
                comment: "Account removal confirmation."
            ),
            selectedAccountTitle
        )
    }

    var removalAlertMessage: String {
        String(
            format: NSLocalizedString(
                "This will delete your currently set up account “%@”.",
                comment: "Account removal confirmation informative text."
            ),
            selectedAccountTitle
        )
    }

    var defaultSIPAddress: String {
        guard !draft.domain.isEmpty else { return "" }
        return SIPAddress(user: draft.username, host: draft.domain).stringValue
    }

    var descriptionPlaceholder: String {
        draft.sipAddress.isEmpty ? defaultSIPAddress : draft.sipAddress
    }

    var proxyPortPlaceholder: String {
        draft.transport == AKSIPAccountKeys.transportTLS ? "5061" : "5060"
    }

    var proxyPortInvalid: Bool {
        draft.usesProxy && !SIPPortValidation.isValid(draft.proxyPort)
    }

    func reload() {
        let previousSelection = selection
        accounts = summaries(from: storedAccounts())

        let nextSelection: String?
        if let previousSelection,
           accounts.contains(where: { $0.id == previousSelection }) {
            nextSelection = previousSelection
        } else {
            nextSelection = accounts.first?.id
        }

        select(nextSelection)
    }

    func reloadAccount(at index: Int) {
        let stored = storedAccounts()
        guard stored.indices.contains(index) else {
            reload()
            return
        }

        let identifier = stringValue(stored[index][AKSIPAccountKeys.uuid])
        accounts = summaries(from: stored)
        select(identifier)
    }

    func flushPendingChanges() {
        persistSelectedDraftNow()
    }

    func addAccount() {
        guard !accountListInteractionDisabled else { return }
        flushPendingChanges()
        guard canAddAccount else { return }
        presentAddAccount?()
    }

    func requestRemoval() {
        guard !accountListInteractionDisabled, selection != nil else {
            return
        }
        pendingRemovalID = selection
    }

    func cancelRemoval() {
        pendingRemovalID = nil
    }

    func confirmRemoval() {
        guard
            !accountListInteractionDisabled,
            let identifier = pendingRemovalID
        else {
            return
        }
        pendingRemovalID = nil

        autosaveTask?.cancel()
        autosaveTask = nil
        hasUnsavedDraft = false

        var stored = storedAccounts()
        guard let index = storedAccountIndex(for: identifier, in: stored) else {
            reload()
            return
        }

        let removedAccount = stored[index]
        let uuid = stringValue(removedAccount[AKSIPAccountKeys.uuid])
        deleteCredentials(
            service: credentialService(
                registrar: stringValue(
                    removedAccount[AKSIPAccountKeys.registrar]
                ),
                domain: stringValue(
                    removedAccount[AKSIPAccountKeys.domain]
                )
            ),
            account: trimmed(
                stringValue(removedAccount[AKSIPAccountKeys.username])
            )
        )
        stored.remove(at: index)
        defaults.set(stored, forKey: UserDefaultsKeys.accounts)

        NotificationCenter.default.post(
            name: .AKPreferencesControllerDidRemoveAccount,
            object: preferencesController,
            userInfo: [
                PreferencesNotificationKey.accountIndex: index,
                AKSIPAccountKeys.uuid: uuid,
            ]
        )

        accounts = summaries(from: stored)
        let nextSelection = stored.isEmpty
            ? nil
            : accounts[min(index, accounts.count - 1)].id
        select(nextSelection)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != draft.isEnabled else { return }

        if enabled {
            enableSelectedAccount()
        } else {
            disableSelectedAccount()
        }
    }

    func moveAccounts(from offsets: IndexSet, to destination: Int) {
        guard !accountListInteractionDisabled else { return }
        guard offsets.count == 1, let source = offsets.first else { return }
        guard destination != source, destination != source + 1 else { return }

        flushPendingChanges()

        var stored = storedAccounts()
        guard
            stored.indices.contains(source),
            destination >= 0,
            destination <= stored.count
        else {
            return
        }

        let moving = stored.remove(at: source)
        let insertionIndex = source < destination ? destination - 1 : destination
        stored.insert(moving, at: insertionIndex)

        saveAccounts(stored)

        NotificationCenter.default.post(
            name: .AKPreferencesControllerDidSwapAccounts,
            object: preferencesController,
            userInfo: [
                PreferencesNotificationKey.sourceIndex: source,
                PreferencesNotificationKey.destinationIndex: destination,
            ]
        )
    }

    func dismissCredentialsError() {
        showsCredentialsError = false
    }

    private func accountDidAdd() {
        let stored = storedAccounts()
        accounts = summaries(from: stored)
        select(accounts.last?.id)
    }

    private func select(_ identifier: String?) {
        guard selection == identifier else {
            selection = identifier
            return
        }
        persistSelectedDraftNow()
        loadSelectedDraft()
    }

    private func draftDidChange(from oldValue: AccountSettingsDraft) {
        guard
            !isApplyingDraft,
            draft != oldValue,
            !draft.isEnabled
        else {
            return
        }

        hasUnsavedDraft = true
        if credentialValuesChanged(from: oldValue) {
            credentialsAreDirty = true
        }
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        guard !passwordIsLoading else { return }

        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }

            self?.persistSelectedDraftNow(saveCredentials: false)
        }
    }

    private func persistSelectedDraftNow(
        saveCredentials: Bool = true
    ) {
        autosaveTask?.cancel()
        autosaveTask = nil

        guard
            !draft.isEnabled,
            let selection
        else {
            return
        }

        if hasUnsavedDraft {
            var stored = storedAccounts()
            guard let index = storedAccountIndex(for: selection, in: stored) else {
                return
            }

            var account = stored[index]
            draft.write(to: &account)
            stored[index] = account
            saveAccounts(stored)
            hasUnsavedDraft = false
        }

        guard
            saveCredentials,
            credentialsAreDirty,
            !passwordIsLoading
        else {
            return
        }

        saveCredentialsIfNeeded(
            service: credentialService(
                registrar: draft.registrar,
                domain: draft.domain
            ),
            account: trimmed(draft.username),
            password: draft.password,
            selection: selection
        )
    }

    private func disableSelectedAccount() {
        guard let selection else { return }

        var stored = storedAccounts()
        guard let index = storedAccountIndex(for: selection, in: stored) else {
            return
        }

        stored[index][UserDefaultsKeys.accountEnabled] = false
        saveAccounts(stored)

        var updatedDraft = draft
        updatedDraft.isEnabled = false
        applyDraft(updatedDraft)
        hasUnsavedDraft = false
        credentialsAreDirty = false

        postEnabledChange(index: index)
    }

    private func enableSelectedAccount() {
        guard
            !passwordIsLoading,
            !credentialsAreSaving,
            !proxyPortInvalid,
            let selection
        else {
            return
        }

        autosaveTask?.cancel()
        autosaveTask = nil

        let stored = storedAccounts()
        guard let index = storedAccountIndex(for: selection, in: stored) else {
            return
        }

        var account = stored[index]
        draft.write(to: &account)

        let service = credentialService(
            registrar: draft.registrar,
            domain: draft.domain
        )
        let username = trimmed(draft.username)
        let password = draft.password
        guard !credentialsMatchLoaded(
            service: service,
            account: username,
            password: password
        ) else {
            commitEnabledAccount(
                account,
                selection: selection,
                service: service,
                username: username,
                password: password
            )
            return
        }

        saveCredentialChanges(
            password: password,
            service: service,
            account: username
        ) { [weak self] in
            self?.commitEnabledAccount(
                account,
                selection: selection,
                service: service,
                username: username,
                password: password
            )
        }
    }

    private func commitEnabledAccount(
        _ accountValue: [String: Any],
        selection: String,
        service: String,
        username: String,
        password: String
    ) {
        var stored = storedAccounts()
        guard let index = storedAccountIndex(for: selection, in: stored) else {
            deleteCredentials(service: service, account: username)
            return
        }

        var account = accountValue
        account[UserDefaultsKeys.accountEnabled] = true
        stored[index] = account
        saveAccounts(stored)

        if self.selection == selection {
            loadedCredentials = LoadedAccountCredentials(
                service: service,
                account: username,
                password: password
            )
            hasUnsavedDraft = false
            credentialsAreDirty = false

            var updatedDraft = draft
            updatedDraft.isEnabled = true
            applyDraft(updatedDraft)
        }

        postEnabledChange(index: index)
    }

    private func postEnabledChange(index: Int) {
        NotificationCenter.default.post(
            name: .AKPreferencesControllerDidChangeAccountEnabled,
            object: preferencesController,
            userInfo: [PreferencesNotificationKey.accountIndex: index]
        )
    }

    private func loadSelectedDraft() {
        passwordLoadTask?.cancel()
        passwordLoadTask = nil
        passwordIsLoading = false
        loadedCredentials = LoadedAccountCredentials()
        hasUnsavedDraft = false
        credentialsAreDirty = false

        guard let selection else {
            applyDraft(AccountSettingsDraft())
            return
        }

        let stored = storedAccounts()
        guard let index = storedAccountIndex(for: selection, in: stored) else {
            applyDraft(AccountSettingsDraft())
            return
        }

        let loaded = AccountSettingsDraft(storedAccount: stored[index])
        applyDraft(loaded)
        loadPassword(
            service: credentialService(registrar: loaded.registrar, domain: loaded.domain),
            account: loaded.username,
            selection: selection
        )
    }

    private func applyDraft(_ value: AccountSettingsDraft) {
        isApplyingDraft = true
        draft = value
        isApplyingDraft = false
    }

    private func loadPassword(
        service: String,
        account: String,
        selection: String
    ) {
        passwordIsLoading = true
        passwordLoadTask = Task { [weak self] in
            guard let self else { return }

            let password = await credentials.password(
                service: service,
                account: account
            )

            guard !Task.isCancelled, self.selection == selection else { return }

            passwordIsLoading = false
            loadedCredentials = LoadedAccountCredentials(
                service: service,
                account: account,
                password: password
            )

            // A slow Keychain read must not fill a different SIP identity.
            if draft.password.isEmpty,
               draft.username == account,
               credentialService(registrar: draft.registrar, domain: draft.domain) == service {
                var updatedDraft = draft
                updatedDraft.password = password
                applyDraft(updatedDraft)
            }

            if hasUnsavedDraft {
                scheduleAutosave()
            }
        }
    }

    private func saveCredentialsIfNeeded(
        service: String,
        account: String,
        password: String,
        selection: String
    ) {
        guard !credentialsMatchLoaded(
            service: service,
            account: account,
            password: password
        ) else {
            credentialsAreDirty = false
            return
        }

        saveCredentialChanges(
            password: password,
            service: service,
            account: account
        ) { [weak self] in
            guard let self, self.selection == selection else { return }
            self.loadedCredentials = LoadedAccountCredentials(
                service: service,
                account: account,
                password: password
            )
            self.credentialsAreDirty = false
        }
    }

    /// Serialize Keychain changes for both account enable and ordinary saves.
    /// Keep editing locked until the previous identity has been retired.
    private func saveCredentialChanges(
        password: String,
        service: String,
        account: String,
        onSuccess: @escaping @MainActor () -> Void
    ) {
        guard !credentialsAreSaving else { return }

        let previousService = loadedCredentials.service
        let previousAccount = loadedCredentials.account
        credentialsAreSaving = true

        Task { [weak self] in
            guard let self else { return }

            let success = await credentials.savePassword(
                password,
                service: service,
                account: account
            )
            guard success else {
                credentialsAreSaving = false
                showsCredentialsError = true
                return
            }

            let removedPrevious = await deletePreviousCredentialsIfNeeded(
                previousService: previousService,
                previousAccount: previousAccount,
                newService: service,
                newAccount: account
            )
            credentialsAreSaving = false
            guard removedPrevious else {
                showsCredentialsError = true
                return
            }

            onSuccess()
        }
    }

    private func credentialsMatchLoaded(
        service: String,
        account: String,
        password: String
    ) -> Bool {
        loadedCredentials == LoadedAccountCredentials(
            service: service,
            account: account,
            password: password
        )
    }

    private func credentialValuesChanged(
        from oldValue: AccountSettingsDraft
    ) -> Bool {
        let oldService = credentialService(
            registrar: oldValue.registrar,
            domain: oldValue.domain
        )
        let newService = credentialService(
            registrar: draft.registrar,
            domain: draft.domain
        )

        return oldService != newService
            || trimmed(oldValue.username) != trimmed(draft.username)
            || oldValue.password != draft.password
    }

    private func deleteCredentials(
        service: String,
        account: String
    ) {
        guard !service.isEmpty, !account.isEmpty else {
            return
        }

        Task {
            _ = await credentials.deletePassword(
                service: service,
                account: account
            )
        }
    }

    private func deletePreviousCredentialsIfNeeded(
        previousService: String,
        previousAccount: String,
        newService: String,
        newAccount: String
    ) async -> Bool {
        guard
            !previousService.isEmpty,
            !previousAccount.isEmpty,
            previousService != newService || previousAccount != newAccount
        else {
            return true
        }

        return await credentials.deletePassword(
            service: previousService,
            account: previousAccount
        )
    }

    private func credentialService(
        registrar: String,
        domain: String
    ) -> String {
        let normalizedRegistrar = trimmed(registrar)
        let normalizedDomain = trimmed(domain)
        return "SIP: \(normalizedRegistrar.isEmpty ? normalizedDomain : normalizedRegistrar)"
    }

    private func summaries(
        from stored: [[String: Any]]
    ) -> [AccountSettingsSummary] {
        stored.map { AccountSettingsSummary(storedAccount: $0) }
    }

    private func saveAccounts(_ stored: [[String: Any]]) {
        defaults.set(stored, forKey: UserDefaultsKeys.accounts)
        accounts = summaries(from: stored)
    }

    private func storedAccountIndex(
        for identifier: String,
        in stored: [[String: Any]]
    ) -> Int? {
        stored.firstIndex {
            stringValue($0[AKSIPAccountKeys.uuid]) == identifier
        }
    }

    private func storedAccounts() -> [[String: Any]] {
        defaults.array(
            forKey: UserDefaultsKeys.accounts
        ) as? [[String: Any]] ?? []
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stringValue(
        _ value: Any?,
        defaultValue: String = ""
    ) -> String {
        value as? String ?? defaultValue
    }
}



