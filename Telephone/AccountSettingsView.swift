//
//  AccountSettingsView.swift
//  Telephone
//

import Cocoa
import Observation
import SwiftUI
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

struct AccountSettingsDraft {
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
        didSet {
            if oldValue != selection {
                loadSelectedDraft()
            }
        }
    }
    var draft = AccountSettingsDraft()
    var pendingRemovalID: String?

    var presentAddAccount: (() -> Void)?

    private weak var preferencesController: PreferencesController?
    private let defaults: UserDefaults

    init(
        preferencesController: PreferencesController,
        defaults: UserDefaults = .standard
    ) {
        self.preferencesController = preferencesController
        self.defaults = defaults
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

    func reload() {
        let previousSelection = selection
        accounts = summaries(from: storedAccounts())

        if let previousSelection, accounts.contains(where: { $0.id == previousSelection }) {
            selection = previousSelection
            loadSelectedDraft()
        } else {
            selection = accounts.first?.id
            if selection == nil {
                draft = AccountSettingsDraft()
            }
        }
    }

    func reloadAccount(at index: Int) {
        let stored = storedAccounts()
        guard stored.indices.contains(index) else {
            reload()
            return
        }

        let identifier = stringValue(stored[index][AKSIPAccountKeys.uuid])
        accounts = summaries(from: stored)
        selection = identifier
        loadSelectedDraft()
    }

    func addAccount() {
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

        var stored = storedAccounts()
        guard let index = stored.firstIndex(where: { stringValue($0[AKSIPAccountKeys.uuid]) == identifier }) else {
            reload()
            return
        }

        let uuid = stringValue(stored[index][AKSIPAccountKeys.uuid])
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
        if stored.isEmpty {
            selection = nil
            draft = AccountSettingsDraft()
        } else {
            selection = accounts[min(index, accounts.count - 1)].id
            loadSelectedDraft()
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != draft.isEnabled else { return }

        var stored = storedAccounts()
        guard
            let selection,
            let index = stored.firstIndex(where: { stringValue($0[AKSIPAccountKeys.uuid]) == selection })
        else {
            return
        }

        var account = stored[index]
        account[UserDefaultsKeys.accountEnabled] = enabled

        if enabled {
            saveDraft(into: &account)
        }

        stored[index] = account
        defaults.set(stored, forKey: UserDefaultsKeys.accounts)

        draft.isEnabled = enabled
        accounts = summaries(from: stored)

        if enabled {
            loadSelectedDraft()
        }

        NotificationCenter.default.post(
            name: .AKPreferencesControllerDidChangeAccountEnabled,
            object: preferencesController,
            userInfo: [kAccountIndex: index]
        )
    }

    func moveAccounts(from offsets: IndexSet, to destination: Int) {
        guard offsets.count == 1, let source = offsets.first else { return }
        guard destination != source, destination != source + 1 else { return }

        var stored = storedAccounts()
        guard stored.indices.contains(source), destination >= 0, destination <= stored.count else { return }

        let selected = selection
        let moving = stored[source]
        stored.insert(moving, at: destination)

        if source < destination {
            stored.remove(at: source)
        } else {
            stored.remove(at: source + 1)
        }

        defaults.set(stored, forKey: UserDefaultsKeys.accounts)
        accounts = summaries(from: stored)

        if let selected {
            selection = selected
            loadSelectedDraft()
        }

        NotificationCenter.default.post(
            name: .AKPreferencesControllerDidSwapAccounts,
            object: preferencesController,
            userInfo: [
                kSourceIndex: source,
                kDestinationIndex: destination,
            ]
        )
    }

    @objc private func accountDidAdd(_ notification: Notification) {
        let stored = storedAccounts()
        accounts = summaries(from: stored)
        selection = accounts.last?.id
        loadSelectedDraft()
    }

    private func loadSelectedDraft() {
        guard let selection else {
            draft = AccountSettingsDraft()
            return
        }

        let stored = storedAccounts()
        guard let account = stored.first(where: { stringValue($0[AKSIPAccountKeys.uuid]) == selection }) else {
            draft = AccountSettingsDraft()
            return
        }

        let registrar = stringValue(account[AKSIPAccountKeys.registrar])
        let domain = stringValue(account[AKSIPAccountKeys.domain])
        let username = stringValue(account[AKSIPAccountKeys.username])
        let service = "SIP: \(registrar.isEmpty ? domain : registrar)"

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

        draft = AccountSettingsDraft(
            isEnabled: boolValue(account[UserDefaultsKeys.accountEnabled]),
            descriptionText: stringValue(account[AKSIPAccountKeys.desc]),
            fullName: stringValue(account[AKSIPAccountKeys.fullName]),
            domain: domain,
            username: username,
            password: AKKeychain.password(forService: service, account: username),
            sipAddress: stringValue(account[AKSIPAccountKeys.sipAddress]),
            registrar: registrar,
            reregistrationTime: positiveIntegerString(account[AKSIPAccountKeys.reregistrationTime]),
            substitutesPlusCharacter: boolValue(account[UserDefaultsKeys.substitutePlusCharacter]),
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
    }

    private func saveDraft(into account: inout [String: Any]) {
        let description = trimmed(draft.descriptionText)
        let fullName = trimmed(draft.fullName)
        let domain = trimmed(draft.domain)
        let username = trimmed(draft.username)
        let registrar = trimmed(draft.registrar)
        let sipAddress = trimmed(draft.sipAddress)
        let proxyHost = trimmed(draft.proxyHost)

        account[AKSIPAccountKeys.desc] = description
        account[AKSIPAccountKeys.fullName] = fullName
        account[AKSIPAccountKeys.domain] = domain
        account[AKSIPAccountKeys.username] = username
        account[AKSIPAccountKeys.reregistrationTime] = integerValue(draft.reregistrationTime)
        account[UserDefaultsKeys.substitutePlusCharacter] = draft.substitutesPlusCharacter
        account[UserDefaultsKeys.plusCharacterSubstitutionString] = draft.plusCharacterSubstitution
        account[AKSIPAccountKeys.useProxy] = draft.usesProxy
        account[AKSIPAccountKeys.proxyHost] = proxyHost
        account[AKSIPAccountKeys.proxyPort] = integerValue(draft.proxyPort)
        account[AKSIPAccountKeys.sipAddress] = sipAddress
        account[AKSIPAccountKeys.registrar] = registrar
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

        let service = "SIP: \(registrar.isEmpty ? domain : registrar)"
        let savedPassword = AKKeychain.password(forService: service, account: username)
        if savedPassword != draft.password {
            _ = AKKeychain.addItem(withService: service, account: username, password: draft.password)
        }
    }

    private func summaries(from stored: [[String: Any]]) -> [AccountSettingsSummary] {
        stored.map { account in
            let identifier = stringValue(account[AKSIPAccountKeys.uuid])
            let description = stringValue(account[AKSIPAccountKeys.desc])
            let explicitAddress = stringValue(account[AKSIPAccountKeys.sipAddress])
            let username = stringValue(account[AKSIPAccountKeys.username])
            let domain = stringValue(account[AKSIPAccountKeys.domain])
            let fallbackAddress = SIPAddress(user: username, host: domain).stringValue
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
        defaults.array(forKey: UserDefaultsKeys.accounts) as? [[String: Any]] ?? []
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

    private func stringValue(_ value: Any?, defaultValue: String = "") -> String {
        value as? String ?? defaultValue
    }
}

struct AccountSettingsView: View {
    @Bindable var model: AccountSettingsModel

    var body: some View {
        HStack(spacing: 0) {
            accountList
            Divider()
            editor
        }
        .alert(model.removalAlertTitle, isPresented: removalPresented) {
            Button(NSLocalizedString("Delete", comment: "Delete button."), role: .destructive) {
                model.confirmRemoval()
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel button."), role: .cancel) {
                model.cancelRemoval()
            }
        } message: {
            Text(model.removalAlertMessage)
        }
        .onAppear {
            model.reload()
        }
    }

    private var accountList: some View {
        VStack(spacing: 0) {
            List(selection: $model.selection) {
                ForEach(model.accounts) { account in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(account.isEnabled ? Color.green : Color.secondary.opacity(0.45))
                            .frame(width: 7, height: 7)

                        Text(account.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .tag(account.id)
                }
                .onMove(perform: model.moveAccounts)
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 6) {
                Button {
                    model.addAccount()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(!model.canAddAccount)
                .help(NSLocalizedString("Add Account", comment: "Add account button."))

                Button {
                    model.requestRemoval()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(!model.hasSelection)
                .help(NSLocalizedString("Remove Account", comment: "Remove account button."))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .frame(width: 205)
    }

    @ViewBuilder
    private var editor: some View {
        if model.hasSelection {
            Form {
                Section(NSLocalizedString("Account Information", comment: "Account settings section.")) {
                    Toggle(
                        NSLocalizedString("Enable this account", comment: "Account settings toggle."),
                        isOn: enabled
                    )

                    if model.draft.isEnabled {
                        Label(
                            NSLocalizedString(
                                "Disable account to change settings.",
                                comment: "Enabled account editing hint."
                            ),
                            systemImage: "lock"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Group {
                        LabeledContent(NSLocalizedString("Description", comment: "Account settings label.")) {
                            TextField(
                                "",
                                text: $model.draft.descriptionText,
                                prompt: Text(model.descriptionPlaceholder)
                            )
                        }
                        LabeledContent(NSLocalizedString("Full Name", comment: "Account settings label.")) {
                            TextField("", text: $model.draft.fullName)
                        }
                        LabeledContent(NSLocalizedString("Domain", comment: "Account settings label.")) {
                            TextField("", text: $model.draft.domain)
                        }
                        LabeledContent(NSLocalizedString("User Name", comment: "Account settings label.")) {
                            TextField("", text: $model.draft.username)
                        }
                        LabeledContent(NSLocalizedString("Password", comment: "Account settings label.")) {
                            SecureField("", text: $model.draft.password)
                        }
                    }
                    .disabled(model.draft.isEnabled)
                }

                Section(NSLocalizedString("Network", comment: "Account settings section.")) {
                    Toggle(
                        NSLocalizedString("Connect using proxy", comment: "Account proxy toggle."),
                        isOn: $model.draft.usesProxy
                    )

                    LabeledContent(NSLocalizedString("Server", comment: "Account settings label.")) {
                        TextField("", text: $model.draft.proxyHost)
                    }
                    .disabled(!model.draft.usesProxy)

                    LabeledContent(NSLocalizedString("Port", comment: "Account settings label.")) {
                        TextField(
                            "",
                            text: $model.draft.proxyPort,
                            prompt: Text(model.proxyPortPlaceholder)
                        )
                        .frame(width: 120)
                    }
                    .disabled(!model.draft.usesProxy)

                    Picker(
                        NSLocalizedString("SIP Transport", comment: "Account settings label."),
                        selection: $model.draft.transport
                    ) {
                        Text("UDP").tag(AKSIPAccountKeys.transportUDP)
                        Text("TCP").tag(AKSIPAccountKeys.transportTCP)
                        Text("TLS").tag(AKSIPAccountKeys.transportTLS)
                    }
                    .pickerStyle(.segmented)

                    Picker(
                        NSLocalizedString("IP Version", comment: "Account settings label."),
                        selection: $model.draft.ipVersion
                    ) {
                        Text("IPv4").tag(AKSIPAccountKeys.ipVersion4)
                        Text("IPv6").tag(AKSIPAccountKeys.ipVersion6)
                    }
                    .pickerStyle(.segmented)

                    Picker(
                        NSLocalizedString("Update IP address", comment: "Account settings label."),
                        selection: $model.draft.ipUpdateMode
                    ) {
                        ForEach(AccountIPUpdateMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(
                        NSLocalizedString(
                            "Enabling this option may solve some audio problems.",
                            comment: "Account IP address update help text."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .disabled(model.draft.isEnabled)

                Section(NSLocalizedString("Advanced", comment: "Account settings section.")) {
                    LabeledContent(NSLocalizedString("SIP Address", comment: "Account settings label.")) {
                        TextField(
                            "",
                            text: $model.draft.sipAddress,
                            prompt: Text(model.defaultSIPAddress)
                        )
                    }

                    LabeledContent(NSLocalizedString("Registry Server", comment: "Account settings label.")) {
                        TextField(
                            "",
                            text: $model.draft.registrar,
                            prompt: Text(model.draft.domain)
                        )
                    }

                    LabeledContent(NSLocalizedString("Reregister every", comment: "Account settings label.")) {
                        HStack(spacing: 6) {
                            TextField(
                                "",
                                text: $model.draft.reregistrationTime,
                                prompt: Text("300")
                            )
                            .frame(width: 90)
                            Text(NSLocalizedString("seconds", comment: "Account settings unit."))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Toggle(
                            NSLocalizedString("Replace “+” with", comment: "Account settings toggle."),
                            isOn: $model.draft.substitutesPlusCharacter
                        )

                        TextField("", text: $model.draft.plusCharacterSubstitution)
                            .frame(width: 100)
                            .disabled(!model.draft.substitutesPlusCharacter)
                    }
                }
                .disabled(model.draft.isEnabled)
            }
            .formStyle(.grouped)
            .padding(.horizontal, 6)
        } else {
            ContentUnavailableView {
                Label(
                    NSLocalizedString("No Account Selected", comment: "Empty account settings title."),
                    systemImage: "at"
                )
            } description: {
                Text(
                    NSLocalizedString(
                        "Select an account to edit its settings.",
                        comment: "Empty account settings description."
                    )
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { model.draft.isEnabled },
            set: model.setEnabled
        )
    }

    private var removalPresented: Binding<Bool> {
        Binding(
            get: { model.pendingRemovalID != nil },
            set: { isPresented in
                if !isPresented {
                    model.cancelRemoval()
                }
            }
        )
    }
}
