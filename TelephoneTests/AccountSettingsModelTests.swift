//
//  AccountSettingsModelTests.swift
//  TelephoneTests
//

import Foundation
import Testing
@testable import Telephone

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

    private let loadedPassword: String
    private let saveSucceeds: Bool
    private var saves: [SavedCredential] = []

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

    func saveCount() -> Int {
        saves.count
    }

    func savedCredentials() -> [SavedCredential] {
        saves
    }
}
