//
//  AccountSettingsModel.swift
//  Telephone
//

import Foundation
import Observation
import UseCases

private let accountSetupDidAddNotification = Notification.Name("AKAccountSetupControllerDidAddAccount")
private let maximumAccountCount = 32

struct AccountSettingsSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let isEnabled: Bool
}

enum AccountIPUpdateMode: Int, CaseIterable, Hashable {
    case off
    case partial
    case all

    var title: String {
        switch self {
        case .off:
            NSLocalizedString("Off", comment: "Account IP address update mode.")
        case .partial:
            NSLocalizedString("Partial", comment: "Account IP address update mode.")
        case .all:
            NSLocalizedString("All", comment: "Account IP address update mode.")
        }
    }
}

struct AccountSettingsDraft: Equatable {
    var isEnabled = false
    var descriptionText = ""
    var fullName = ""
    var domain = ""
    var username = ""
    var password = ""
    var sipAddress = ""
    var registrar = ""
    var reregistrationTime = ""
    var substitutesPlusCharacter = false
    var plusCharacterSubstitution = "00"
    var usesProxy = false
    var proxyHost = ""
    var proxyPort = ""
    var transport = AKSIPAccountKeys.transportUDP
    var ipVersion = AKSIPAccountKeys.ipVersion4
    var ipUpdateMode: AccountIPUpdateMode = .all
}

@MainActor
@Observable
final class AccountSettingsModel: NSObject {
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
    private var credentialSaveGeneration = 0

    @ObservationIgnored
    private var isApplyingDraft = false

    @ObservationIgnored
    private var hasUnsavedDraft = false

    @ObservationIgnored
    private var credentialsAreDirty = false

    @ObservationIgnored
    private var loadedPassword = ""

    @ObservationIgnored
    private var loadedPasswordService = ""

    @ObservationIgnored
    private var loadedPasswordAccount = ""

    init(
        preferencesController: AnyObject?,
        defaults: UserDefaults = .standard,
        credentials: any CredentialsStoring
    ) {
        self.preferencesController = preferencesController
        self.defaults = defaults
        self.credentials = credentials
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accountDidAdd),
            name: accountSetupDidAddNotification,
            object: nil
        )
        reload()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var hasSelection: Bool {
        selection != nil
    }

    var canAddAccount: Bool {
        accounts.count < maximumAccountCount
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

        select(nextSelection, reloadIfUnchanged: true)
    }

    func reloadAccount(at index: Int) {
        let stored = storedAccounts()
        guard stored.indices.contains(index) else {
            reload()
            return
        }

        let identifier = stringValue(stored[index][AKSIPAccountKeys.uuid])
        accounts = summaries(from: stored)
        select(identifier, reloadIfUnchanged: true)
    }

    func flushPendingChanges() {
        persistSelectedDraftNow()
    }

    func addAccount() {
        flushPendingChanges()
        guard canAddAccount else { return }
        presentAddAccount?()
    }

    func requestRemoval() {
        guard selection != nil else { return }
        pendingRemovalID = selection
    }

    func cancelRemoval() {
        pendingRemovalID = nil
    }

    func confirmRemoval() {
        guard let identifier = pendingRemovalID else { return }
        pendingRemovalID = nil

        autosaveTask?.cancel()
        autosaveTask = nil
        hasUnsavedDraft = false

        var stored = storedAccounts()
        guard let index = stored.firstIndex(where: {
            stringValue($0[AKSIPAccountKeys.uuid]) == identifier
        }) else {
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
                kAccountIndex: index,
                AKSIPAccountKeys.uuid: uuid,
            ]
        )

        accounts = summaries(from: stored)
        let nextSelection = stored.isEmpty
            ? nil
            : accounts[min(index, accounts.count - 1)].id
        select(nextSelection, reloadIfUnchanged: true)
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

        let moving = stored[source]
        stored.insert(moving, at: destination)

        if source < destination {
            stored.remove(at: source)
        } else {
            stored.remove(at: source + 1)
        }

        defaults.set(stored, forKey: UserDefaultsKeys.accounts)
        accounts = summaries(from: stored)

        NotificationCenter.default.post(
            name: .AKPreferencesControllerDidSwapAccounts,
            object: preferencesController,
            userInfo: [
                kSourceIndex: source,
                kDestinationIndex: destination,
            ]
        )
    }

    func dismissCredentialsError() {
        showsCredentialsError = false
    }

    @objc
    private func accountDidAdd(_ notification: Notification) {
        let stored = storedAccounts()
        accounts = summaries(from: stored)
        select(accounts.last?.id, reloadIfUnchanged: true)
    }

    private func select(
        _ identifier: String?,
        reloadIfUnchanged: Bool
    ) {
        if selection == identifier {
            if reloadIfUnchanged {
                persistSelectedDraftNow()
                loadSelectedDraft()
            }
        } else {
            selection = identifier
        }
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
            !passwordIsLoading,
            let selection
        else {
            return
        }

        if hasUnsavedDraft {
            var stored = storedAccounts()
            guard let index = stored.firstIndex(where: {
                stringValue($0[AKSIPAccountKeys.uuid]) == selection
            }) else {
                return
            }

            var account = stored[index]
            applyDraft(to: &account)
            stored[index] = account
            defaults.set(stored, forKey: UserDefaultsKeys.accounts)
            accounts = summaries(from: stored)
            hasUnsavedDraft = false
        }

        guard saveCredentials, credentialsAreDirty else {
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
        guard let index = stored.firstIndex(where: {
            stringValue($0[AKSIPAccountKeys.uuid]) == selection
        }) else {
            return
        }

        stored[index][UserDefaultsKeys.accountEnabled] = false
        defaults.set(stored, forKey: UserDefaultsKeys.accounts)

        isApplyingDraft = true
        draft.isEnabled = false
        isApplyingDraft = false
        hasUnsavedDraft = false
        credentialsAreDirty = false
        accounts = summaries(from: stored)

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
        guard let index = stored.firstIndex(where: {
            stringValue($0[AKSIPAccountKeys.uuid]) == selection
        }) else {
            return
        }

        var account = stored[index]
        applyDraft(to: &account)

        let service = credentialService(
            registrar: draft.registrar,
            domain: draft.domain
        )
        let username = trimmed(draft.username)
        let password = draft.password
        let previousService = loadedPasswordService
        let previousAccount = loadedPasswordAccount

        let needsCredentialSave =
            loadedPasswordService != service
            || loadedPasswordAccount != username
            || loadedPassword != password

        guard needsCredentialSave else {
            commitEnabledAccount(
                account,
                selection: selection,
                service: service,
                username: username,
                password: password
            )
            return
        }

        credentialsAreSaving = true
        credentialSaveGeneration &+= 1
        let generation = credentialSaveGeneration

        Task { [weak self] in
            guard let self else { return }

            let success = await credentials.savePassword(
                password,
                service: service,
                account: username
            )

            guard generation == credentialSaveGeneration else { return }
            credentialsAreSaving = false

            guard success else {
                showsCredentialsError = true
                return
            }

            await deletePreviousCredentialsIfNeeded(
                previousService: previousService,
                previousAccount: previousAccount,
                newService: service,
                newAccount: username
            )

            commitEnabledAccount(
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
        guard let index = stored.firstIndex(where: {
            stringValue($0[AKSIPAccountKeys.uuid]) == selection
        }) else {
            return
        }

        var account = accountValue
        account[UserDefaultsKeys.accountEnabled] = true
        stored[index] = account
        defaults.set(stored, forKey: UserDefaultsKeys.accounts)
        accounts = summaries(from: stored)

        if self.selection == selection {
            loadedPassword = password
            loadedPasswordService = service
            loadedPasswordAccount = username
            hasUnsavedDraft = false
            credentialsAreDirty = false

            isApplyingDraft = true
            draft.isEnabled = true
            isApplyingDraft = false
        }

        postEnabledChange(index: index)
    }

    private func postEnabledChange(index: Int) {
        NotificationCenter.default.post(
            name: .AKPreferencesControllerDidChangeAccountEnabled,
            object: preferencesController,
            userInfo: [kAccountIndex: index]
        )
    }

    private func loadSelectedDraft() {
        passwordLoadTask?.cancel()
        passwordLoadTask = nil
        passwordIsLoading = false
        loadedPassword = ""
        loadedPasswordService = ""
        loadedPasswordAccount = ""
        hasUnsavedDraft = false
        credentialsAreDirty = false

        guard let selection else {
            applyDraft(AccountSettingsDraft())
            return
        }

        let stored = storedAccounts()
        guard let account = stored.first(where: {
            stringValue($0[AKSIPAccountKeys.uuid]) == selection
        }) else {
            applyDraft(AccountSettingsDraft())
            return
        }

        let registrar = stringValue(account[AKSIPAccountKeys.registrar])
        let domain = stringValue(account[AKSIPAccountKeys.domain])
        let username = stringValue(account[AKSIPAccountKeys.username])

        let updateContact = boolValue(account[AKSIPAccountKeys.updateContactHeader])
        let updateVia = boolValue(account[AKSIPAccountKeys.updateViaHeader])
        let updateSDP = boolValue(account[AKSIPAccountKeys.updateSDP])
        let updateMode: AccountIPUpdateMode
        if updateContact && updateVia && updateSDP {
            updateMode = .all
        } else if updateContact || updateVia || updateSDP {
            updateMode = .partial
        } else {
            updateMode = .off
        }

        applyDraft(
            AccountSettingsDraft(
                isEnabled: boolValue(account[UserDefaultsKeys.accountEnabled]),
                descriptionText: stringValue(account[AKSIPAccountKeys.desc]),
                fullName: stringValue(account[AKSIPAccountKeys.fullName]),
                domain: domain,
                username: username,
                password: "",
                sipAddress: stringValue(account[AKSIPAccountKeys.sipAddress]),
                registrar: registrar,
                reregistrationTime: positiveIntegerString(
                    account[AKSIPAccountKeys.reregistrationTime]
                ),
                substitutesPlusCharacter: boolValue(
                    account[UserDefaultsKeys.substitutePlusCharacter]
                ),
                plusCharacterSubstitution: stringValue(
                    account[UserDefaultsKeys.plusCharacterSubstitutionString],
                    defaultValue: "00"
                ),
                usesProxy: boolValue(account[AKSIPAccountKeys.useProxy]),
                proxyHost: stringValue(account[AKSIPAccountKeys.proxyHost]),
                proxyPort: positiveIntegerString(account[AKSIPAccountKeys.proxyPort]),
                transport: stringValue(
                    account[AKSIPAccountKeys.transport],
                    defaultValue: AKSIPAccountKeys.transportUDP
                ),
                ipVersion: stringValue(
                    account[AKSIPAccountKeys.ipVersion],
                    defaultValue: AKSIPAccountKeys.ipVersion4
                ),
                ipUpdateMode: updateMode
            )
        )

        loadPassword(
            service: credentialService(registrar: registrar, domain: domain),
            account: username,
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

            guard
                !Task.isCancelled,
                self.selection == selection,
                self.draft.username == account
            else {
                return
            }

            passwordIsLoading = false
            loadedPassword = password
            loadedPasswordService = service
            loadedPasswordAccount = account

            if draft.password.isEmpty {
                isApplyingDraft = true
                draft.password = password
                isApplyingDraft = false
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
        let unchanged =
            loadedPasswordService == service
            && loadedPasswordAccount == account
            && loadedPassword == password
        guard !unchanged else {
            credentialsAreDirty = false
            return
        }

        let previousService = loadedPasswordService
        let previousAccount = loadedPasswordAccount

        credentialsAreSaving = true
        credentialSaveGeneration &+= 1
        let generation = credentialSaveGeneration

        Task { [weak self] in
            guard let self else { return }

            let success = await credentials.savePassword(
                password,
                service: service,
                account: account
            )

            guard generation == credentialSaveGeneration else { return }
            credentialsAreSaving = false

            guard success else {
                showsCredentialsError = true
                return
            }

            await deletePreviousCredentialsIfNeeded(
                previousService: previousService,
                previousAccount: previousAccount,
                newService: service,
                newAccount: account
            )

            guard self.selection == selection else { return }
            loadedPassword = password
            loadedPasswordService = service
            loadedPasswordAccount = account
            credentialsAreDirty = false
        }
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
    ) async {
        guard
            !previousService.isEmpty,
            !previousAccount.isEmpty,
            previousService != newService || previousAccount != newAccount
        else {
            return
        }

        _ = await credentials.deletePassword(
            service: previousService,
            account: previousAccount
        )
    }

    private func applyDraft(to account: inout [String: Any]) {
        account[AKSIPAccountKeys.desc] = trimmed(draft.descriptionText)
        account[AKSIPAccountKeys.fullName] = trimmed(draft.fullName)
        account[AKSIPAccountKeys.domain] = trimmed(draft.domain)
        account[AKSIPAccountKeys.username] = trimmed(draft.username)
        account[AKSIPAccountKeys.reregistrationTime] =
            integerValue(draft.reregistrationTime)
        account[UserDefaultsKeys.substitutePlusCharacter] =
            draft.substitutesPlusCharacter
        account[UserDefaultsKeys.plusCharacterSubstitutionString] =
            draft.plusCharacterSubstitution
        account[AKSIPAccountKeys.useProxy] = draft.usesProxy
        account[AKSIPAccountKeys.proxyHost] = trimmed(draft.proxyHost)
        if let proxyPort = SIPPortValidation.value(draft.proxyPort) {
            account[AKSIPAccountKeys.proxyPort] = proxyPort
        }
        account[AKSIPAccountKeys.sipAddress] = trimmed(draft.sipAddress)
        account[AKSIPAccountKeys.registrar] = trimmed(draft.registrar)
        account[AKSIPAccountKeys.transport] = draft.transport
        account[AKSIPAccountKeys.ipVersion] = draft.ipVersion

        switch draft.ipUpdateMode {
        case .all:
            account[AKSIPAccountKeys.updateContactHeader] = true
            account[AKSIPAccountKeys.updateViaHeader] = true
            account[AKSIPAccountKeys.updateSDP] = true
        case .partial:
            account[AKSIPAccountKeys.updateContactHeader] = true
            account[AKSIPAccountKeys.updateViaHeader] = true
            account[AKSIPAccountKeys.updateSDP] = false
        case .off:
            account[AKSIPAccountKeys.updateContactHeader] = false
            account[AKSIPAccountKeys.updateViaHeader] = false
            account[AKSIPAccountKeys.updateSDP] = false
        }
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
        stored.map { account in
            let identifier = stringValue(account[AKSIPAccountKeys.uuid])
            let description = stringValue(account[AKSIPAccountKeys.desc])
            let explicitAddress = stringValue(account[AKSIPAccountKeys.sipAddress])
            let username = stringValue(account[AKSIPAccountKeys.username])
            let domain = stringValue(account[AKSIPAccountKeys.domain])
            let fallbackAddress = SIPAddress(
                user: username,
                host: domain
            ).stringValue
            let title = description.isEmpty
                ? (explicitAddress.isEmpty ? fallbackAddress : explicitAddress)
                : description

            return AccountSettingsSummary(
                id: identifier,
                title: title,
                isEnabled: boolValue(account[UserDefaultsKeys.accountEnabled])
            )
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

    private func integerValue(_ value: String) -> Int {
        Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func positiveIntegerString(_ value: Any?) -> String {
        let integer = (value as? NSNumber)?.intValue ?? 0
        return integer > 0 ? String(integer) : ""
    }

    private func boolValue(_ value: Any?) -> Bool {
        (value as? NSNumber)?.boolValue ?? false
    }

    private func stringValue(
        _ value: Any?,
        defaultValue: String = ""
    ) -> String {
        value as? String ?? defaultValue
    }
}

