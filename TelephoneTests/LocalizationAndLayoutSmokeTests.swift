//
//  LocalizationAndLayoutSmokeTests.swift
//  TelephoneTests
//

import Foundation
import Testing

struct LocalizationAndLayoutSmokeTests {
    @Test
    func modernSwiftUIStringsExistInEverySupportedLocalization() throws {
        let sourceFiles = [
            "Telephone/AboutTelephone.swift",
            "Telephone/AccountSettingsModel.swift",
            "Telephone/AccountSettingsView.swift",
            "Telephone/AccountSetupView.swift",
            "Telephone/ApplicationDialogController.swift",
            "Telephone/CallController.m",
            "Telephone/CallControlViews.swift",
            "Telephone/CallPresentationCoordinator.swift",
            "Telephone/CallWindowModel.swift",
            "Telephone/CallHistoryModel.swift",
            "Telephone/CallHistoryScreen.swift",
            "Telephone/CallTransferViews.swift",
            "Telephone/CustomerContextView.swift",
            "Telephone/GeneralSettingsView.swift",
            "Telephone/NetworkSettingsView.swift",
            "Telephone/SettingsModel.swift",
            "Telephone/SoundSettingsView.swift",
            "Telephone/TelephoneApp.swift",
        ]

        var requiredKeys = Set<String>()
        for path in sourceFiles {
            requiredKeys.formUnion(
                try localizedKeys(
                    in: repositoryRoot.appendingPathComponent(path)
                )
            )
        }
        requiredKeys.formUnion(appIntentLocalizationKeys)

        let catalogURL = repositoryRoot.appendingPathComponent(
            "Telephone/Localizable.xcstrings"
        )
        let catalogKeys = try localizationKeys(in: catalogURL)

        for localization in ["en", "de", "ru"] {
            let availableKeys = try localizationKeys(
                in: catalogURL,
                localization: localization
            )
            let missing = requiredKeys.subtracting(availableKeys).sorted()
            let untranslated = catalogKeys.subtracting(availableKeys).sorted()

            #expect(
                missing.isEmpty,
                "Missing \(localization) localization keys: \(missing)"
            )
            #expect(
                untranslated.isEmpty,
                "Untranslated \(localization) catalog keys: \(untranslated)"
            )
        }
    }

    @Test
    @MainActor
    func settingsWindowSizesStayPurposeBuilt() {
        #expect(SettingsSection.general.windowSize.width <= 620)
        #expect(SettingsSection.general.windowSize.height <= 360)

        #expect(SettingsSection.sound.windowSize.width <= 650)
        #expect(SettingsSection.sound.windowSize.height <= 450)

        #expect(SettingsSection.network.windowSize.width <= 660)
        #expect(SettingsSection.network.windowSize.height <= 520)

        #expect(SettingsSection.accounts.windowSize.width <= 740)
        #expect(SettingsSection.accounts.windowSize.height <= 580)

        #expect(
            SettingsSection.general.windowSize.height
                < SettingsSection.accounts.windowSize.height
        )
    }

    private let appIntentLocalizationKeys: Set<String> = [
        "Telephone Account",
        "Account Status",
        "Call with Telephone",
        "Dial with Telephone",
        "Dial",
        "Places a phone or SIP call using Telephone.",
        "Destination",
        "Who would you like to call?",
        "Open Telephone Settings",
        "Opens Telephone settings.",
        "Set Telephone Account Status",
        "Changes the availability status of a Telephone SIP account.",
        "Account",
        "Status",
        "Call",
        "Open Settings",
        "Set Account Status",
        "Telephone is not ready.",
        "Telephone couldn't place this call.",
        "Telephone couldn't update this account.",
        "Telephone supports audio calls only.",
        "Telephone couldn't determine who to call.",
        "Telephone supports one destination per call.",
        "Audio",
        "Video",
    ]

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func localizedKeys(in url: URL) throws -> Set<String> {
        let text = try String(contentsOf: url, encoding: .utf8)
        let pattern = #"NSLocalizedString\(\s*@?"((?:\\.|[^"])*)""#
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)

        return Set(
            expression.matches(in: text, range: range).compactMap { match in
                guard
                    let range = Range(match.range(at: 1), in: text)
                else {
                    return nil
                }
                return String(text[range])
            }
        )
    }

    private func localizationKeys(in url: URL) throws -> Set<String> {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard
            let catalog = object as? [String: Any],
            let strings = catalog["strings"] as? [String: Any]
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Set(strings.keys)
    }

    private func localizationKeys(
        in url: URL,
        localization: String
    ) throws -> Set<String> {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard
            let catalog = object as? [String: Any],
            let strings = catalog["strings"] as? [String: Any]
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return Set(
            strings.compactMap { key, value in
                guard
                    let entry = value as? [String: Any],
                    let localizations = entry["localizations"]
                        as? [String: Any],
                    localizations[localization] != nil
                else {
                    return nil
                }
                return key
            }
        )
    }

}
