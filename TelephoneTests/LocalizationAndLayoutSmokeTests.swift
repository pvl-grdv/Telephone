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
            "Telephone/CallControlViews.swift",
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

        for localization in ["en", "de", "ru"] {
            let path = repositoryRoot.appendingPathComponent(
                "Telephone/\(localization).lproj/Localizable.strings"
            )
            let availableKeys = try localizationKeys(in: path)
            let missing = requiredKeys.subtracting(availableKeys).sorted()

            #expect(
                missing.isEmpty,
                "Missing \(localization) localization keys: \(missing)"
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
    ]

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func localizedKeys(in url: URL) throws -> Set<String> {
        let text = try String(contentsOf: url, encoding: .utf8)
        let pattern = #"NSLocalizedString\(\s*"((?:\\.|[^"])*)""#
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
        let text = try String(contentsOf: url, encoding: .utf8)
        let pattern = #"(?m)^\s*"((?:\\.|[^"])*)"\s*="#
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
}
