//
//  SettingsViewModelTests.swift
//  TelephoneTests
//

import Testing

@MainActor
struct SettingsViewModelTests {
    @Test func initializationDoesNotCreateTabModels() {
        let defaults = makeDefaults()
        var accountCreates = 0
        var soundCreates = 0
        var networkCreates = 0

        _ = SettingsViewModel(
            defaults: defaults,
            accountModelFactory: {
                accountCreates += 1
                fatalError("Account model should stay lazy")
            },
            soundModelFactory: {
                soundCreates += 1
                fatalError("Sound model should stay lazy")
            },
            networkModelFactory: {
                networkCreates += 1
                fatalError("Network model should stay lazy")
            }
        )

        #expect(accountCreates == 0)
        #expect(soundCreates == 0)
        #expect(networkCreates == 0)
    }

    @Test func restoresLastSelectedSection() {
        let defaults = makeDefaults()
        defaults.set(
            SettingsSection.network.rawValue,
            forKey: UserDefaultsKeys.settingsSection
        )

        let sut = SettingsViewModel(
            defaults: defaults,
            accountModelFactory: { fatalError("Unexpected account model") },
            soundModelFactory: { fatalError("Unexpected sound model") },
            networkModelFactory: { fatalError("Unexpected network model") }
        )

        #expect(sut.selection == .network)
    }

    @Test func selectionPersistsImmediately() {
        let defaults = makeDefaults()
        let sut = SettingsViewModel(
            defaults: defaults,
            accountModelFactory: { fatalError("Unexpected account model") },
            soundModelFactory: { fatalError("Unexpected sound model") },
            networkModelFactory: { fatalError("Unexpected network model") }
        )

        sut.selection = .accounts

        #expect(
            defaults.integer(forKey: UserDefaultsKeys.settingsSection)
                == SettingsSection.accounts.rawValue
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SettingsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
