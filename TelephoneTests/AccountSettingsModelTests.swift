//
//  AccountSettingsModelTests.swift
//  TelephoneTests
//

import Foundation
import Testing

@MainActor
struct AccountSettingsModelTests {
    @Test
    func disabledAccountEditsArePersistedWhenFlushed() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        let model = AccountSettingsModel(
            preferencesController: nil,
            defaults: fixture.defaults,
            credentials: fixture.credentials
        )
        await waitForPasswordLoad(model)

        model.draft.descriptionText = "Updated account"
        model.draft.proxyHost = "proxy.example.com"
        model.flushPendingChanges()

        let stored = storedAccounts(in: fixture.defaults)
        #expect(
            stored.first?[AKSIPAccountKeys.desc] as? String
                == "Updated account"
        )
        #expect(
            stored.first?[AKSIPAccountKeys.proxyHost] as? String
                == "proxy.example.com"
        )
    }

    @Test
    func accountListIsLockedDuringCredentialWork() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        let model = AccountSettingsModel(
            preferencesController: nil,
            defaults: fixture.defaults,
            credentials: fixture.credentials
        )

        #expect(model.accountListInteractionDisabled)
        await waitForPasswordLoad(model)
        #expect(!model.accountListInteractionDisabled)

        model.draft.password = "replacement"
        model.setEnabled(true)

        #expect(model.accountListInteractionDisabled)
        model.requestRemoval()
        #expect(model.pendingRemovalID == nil)

        await waitForCredentialSave(fixture.credentials)
        await waitUntil { !model.credentialsAreSaving }
        #expect(!model.accountListInteractionDisabled)
    }

    @Test
    func changedCredentialIdentityUsesNewServiceAndAccount() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        let model = AccountSettingsModel(
            preferencesController: nil,
            defaults: fixture.defaults,
            credentials: fixture.credentials
        )
        await waitForPasswordLoad(model)

        model.draft.domain = "new.example.com"
        model.draft.username = "bob"
        model.draft.password = "new-secret"
        model.flushPendingChanges()

        await waitForCredentialSave(fixture.credentials)
        let saves = await fixture.credentials.savedCredentials()

        #expect(saves.last?.service == "SIP: new.example.com")
        #expect(saves.last?.account == "bob")
        #expect(saves.last?.password == "new-secret")

        let stored = storedAccounts(in: fixture.defaults)
        #expect(
            stored.first?[AKSIPAccountKeys.domain] as? String
                == "new.example.com"
        )
        #expect(
            stored.first?[AKSIPAccountKeys.username] as? String
                == "bob"
        )
    }

    @Test
    func autosaveDoesNotWriteIntermediateCredentialIdentity() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        let model = AccountSettingsModel(
            preferencesController: nil,
            defaults: fixture.defaults,
            credentials: fixture.credentials
        )
        await waitForPasswordLoad(model)

        model.draft.username = "b"
        for _ in 0..<40 {
            await Task.yield()
        }

        #expect(await fixture.credentials.saveCount() == 0)

        model.flushPendingChanges()
        await waitForCredentialSave(fixture.credentials)

        let saves = await fixture.credentials.savedCredentials()
        #expect(saves.last?.account == "b")
    }

    @Test
    func changingCredentialIdentityRemovesOldKeychainItem() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        let model = AccountSettingsModel(
            preferencesController: nil,
            defaults: fixture.defaults,
            credentials: fixture.credentials
        )
        await waitForPasswordLoad(model)

        model.draft.domain = "new.example.com"
        model.draft.username = "bob"
        model.flushPendingChanges()

        await waitForCredentialSave(fixture.credentials)
        await waitUntil {
            !model.credentialsAreSaving
        }

        let deletions = await fixture.credentials.deletedCredentials()
        #expect(
            deletions.contains(
                .init(
                    service: "SIP: old.example.com",
                    account: "alice"
                )
            )
        )
    }

    @Test
    func removingAccountDeletesStoredCredential() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        let model = AccountSettingsModel(
            preferencesController: nil,
            defaults: fixture.defaults,
            credentials: fixture.credentials
        )
        await waitForPasswordLoad(model)

        model.requestRemoval()
        model.confirmRemoval()

        for _ in 0..<200 {
            if !(await fixture.credentials.deletedCredentials()).isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(
            await fixture.credentials.deletedCredentials()
                == [
                    .init(
                        service: "SIP: old.example.com",
                        account: "alice"
                    )
                ]
        )
    }

    @Test
    func movingAccountsInEitherDirectionPreservesTheirUUIDsAndSelection() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        let extra: [[String: Any]] = [
            [AKSIPAccountKeys.uuid: "second", AKSIPAccountKeys.domain: "b.example", AKSIPAccountKeys.username: "bob"],
            [AKSIPAccountKeys.uuid: "third", AKSIPAccountKeys.domain: "c.example", AKSIPAccountKeys.username: "carol"]
        ]
        fixture.defaults.set(
            storedAccounts(in: fixture.defaults) + extra,
            forKey: UserDefaultsKeys.accounts
        )
        let model = AccountSettingsModel(
            preferencesController: nil,
            defaults: fixture.defaults,
            credentials: fixture.credentials
        )
        await waitForPasswordLoad(model)

        model.moveAccounts(from: IndexSet(integer: 0), to: 3)
        #expect(storedAccounts(in: fixture.defaults).compactMap {
            $0[AKSIPAccountKeys.uuid] as? String
        } == ["second", "third", "account-id"])
        #expect(model.selection == "account-id")

        model.moveAccounts(from: IndexSet(integer: 2), to: 0)
        #expect(storedAccounts(in: fixture.defaults).compactMap {
            $0[AKSIPAccountKeys.uuid] as? String
        } == ["account-id", "second", "third"])
        #expect(model.accounts.map(\.id) == ["account-id", "second", "third"])
        #expect(model.selection == "account-id")
    }

    @Test
    func invalidProxyPortDoesNotEnableAccount() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        let model = AccountSettingsModel(
            preferencesController: nil,
            defaults: fixture.defaults,
            credentials: fixture.credentials
        )
        await waitForPasswordLoad(model)

        model.draft.usesProxy = true
        model.draft.proxyPort = "70000"

        #expect(model.proxyPortInvalid)

        model.setEnabled(true)

        #expect(!model.draft.isEnabled)
        #expect(await fixture.credentials.saveCount() == 0)
    }

    @Test
    func failedCredentialSaveDoesNotEnableAccount() async {
        let fixture = makeFixture(saveSucceeds: false)
        defer { fixture.cleanup() }

        let model = AccountSettingsModel(
            preferencesController: nil,
            defaults: fixture.defaults,
            credentials: fixture.credentials
        )
        await waitForPasswordLoad(model)

        model.draft.password = "replacement"
        model.setEnabled(true)

        await waitForCredentialSave(fixture.credentials)
        await waitUntil { !model.credentialsAreSaving }

        #expect(!model.draft.isEnabled)
        #expect(model.showsCredentialsError)

        let stored = storedAccounts(in: fixture.defaults)
        #expect(
            (stored.first?[UserDefaultsKeys.accountEnabled] as? NSNumber)?
                .boolValue == false
        )
    }

    private func makeFixture(
        saveSucceeds: Bool = true
    ) -> AccountSettingsFixture {
        let suiteName =
            "AccountSettingsModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(
            [
                [
                    UserDefaultsKeys.accountEnabled: false,
                    AKSIPAccountKeys.uuid: "account-id",
                    AKSIPAccountKeys.desc: "Original account",
                    AKSIPAccountKeys.fullName: "Alice",
                    AKSIPAccountKeys.domain: "old.example.com",
                    AKSIPAccountKeys.username: "alice",
                    UserDefaultsKeys.plusCharacterSubstitutionString: "00",
                ],
            ],
            forKey: UserDefaultsKeys.accounts
        )

        return AccountSettingsFixture(
            suiteName: suiteName,
            defaults: defaults,
            credentials: CredentialsStoreFake(
                password: "secret",
                saveSucceeds: saveSucceeds
            )
        )
    }

    private func storedAccounts(
        in defaults: UserDefaults
    ) -> [[String: Any]] {
        defaults.array(
            forKey: UserDefaultsKeys.accounts
        ) as? [[String: Any]] ?? []
    }

    private func waitForPasswordLoad(
        _ model: AccountSettingsModel
    ) async {
        await waitUntil { !model.passwordIsLoading }
        #expect(!model.passwordIsLoading)
    }

    private func waitForCredentialSave(
        _ credentials: CredentialsStoreFake
    ) async {
        for _ in 0..<200 {
            if await credentials.saveCount() > 0 {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for credential save.")
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<200 {
            if condition() {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for model state.")
    }
}

private struct AccountSettingsFixture {
    let suiteName: String
    let defaults: UserDefaults
    let credentials: CredentialsStoreFake

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private actor CredentialsStoreFake: CredentialsStoring {
    struct SavedCredential: Sendable {
        let service: String
        let account: String
        let password: String
    }

    struct CredentialIdentity: Sendable, Equatable {
        let service: String
        let account: String
    }

    private let loadedPassword: String
    private let saveSucceeds: Bool
    private var saves: [SavedCredential] = []
    private var deletions: [CredentialIdentity] = []

    init(
        password: String,
        saveSucceeds: Bool
    ) {
        loadedPassword = password
        self.saveSucceeds = saveSucceeds
    }

    func password(
        service: String,
        account: String
    ) async -> String {
        loadedPassword
    }

    func savePassword(
        _ password: String,
        service: String,
        account: String
    ) async -> Bool {
        saves.append(
            SavedCredential(
                service: service,
                account: account,
                password: password
            )
        )
        return saveSucceeds
    }

    func deletePassword(
        service: String,
        account: String
    ) async -> Bool {
        deletions.append(
            CredentialIdentity(
                service: service,
                account: account
            )
        )
        return true
    }

    func saveCount() -> Int {
        saves.count
    }

    func savedCredentials() -> [SavedCredential] {
        saves
    }

    func deletedCredentials() -> [CredentialIdentity] {
        deletions
    }
}

@MainActor
struct AccountSettingsDraftStorageTests {
    @Test func partialIPUpdateFlagsRoundTripWithoutDiscardingAccountIdentity() {
        let stored: [String: Any] = [
            UserDefaultsKeys.accountEnabled: false,
            AKSIPAccountKeys.uuid: "account-id",
            AKSIPAccountKeys.desc: "  Sales  ",
            AKSIPAccountKeys.domain: " example.com ",
            AKSIPAccountKeys.username: " alice ",
            AKSIPAccountKeys.updateContactHeader: true,
            AKSIPAccountKeys.updateViaHeader: true,
            AKSIPAccountKeys.updateSDP: false,
            AKSIPAccountKeys.proxyPort: 5061
        ]
        var draft = AccountSettingsDraft(storedAccount: stored)
        #expect(draft.ipUpdateMode == .partial)
        #expect(draft.proxyPort == "5061")
        draft.descriptionText = " Updated "
        var saved = stored
        draft.write(to: &saved)
        #expect(saved[AKSIPAccountKeys.uuid] as? String == "account-id")
        #expect(saved[AKSIPAccountKeys.desc] as? String == "Updated")
        #expect(saved[AKSIPAccountKeys.domain] as? String == "example.com")
        #expect(saved[AKSIPAccountKeys.updateSDP] as? Bool == false)
    }

    @Test func missingStoredDefaultsAndEachIPModeRoundTrip() {
        let stored: [String: Any] = [AKSIPAccountKeys.domain: "example.com"]
        let draft = AccountSettingsDraft(storedAccount: stored)
        #expect(draft.ipUpdateMode == .off)
        #expect(draft.transport == AKSIPAccountKeys.transportUDP)
        #expect(draft.plusCharacterSubstitution == "00")
        for mode in AccountIPUpdateMode.allCases {
            var editing = draft
            editing.ipUpdateMode = mode
            var result = stored
            editing.write(to: &result)
            #expect(AccountSettingsDraft(storedAccount: result).ipUpdateMode == mode)
        }
    }
}
