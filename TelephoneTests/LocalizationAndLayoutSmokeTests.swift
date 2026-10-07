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
            "Telephone/AccountWindowView.swift",
            "Telephone/ApplicationDialogController.swift",
            "Telephone/CallController.swift",
            "Telephone/CallControlViews.swift",
            "Telephone/CallPresentationCoordinator.swift",
            "Telephone/CallWindowModel.swift",
            "Telephone/CallHistoryModel.swift",
            "Telephone/CallHistoryScreen.swift",
            "Telephone/CallTransferViews.swift",
            "Telephone/CustomerContextView.swift",
            "Telephone/CRMGatewaySettingsView.swift",
            "Telephone/CRMKeyLookupView.swift",
            "Telephone/CRMHistoryLookupView.swift",
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

    @Test @MainActor
    func accountConnectionFailureIsDistinctFromUserUnavailable() throws {
        let viewSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Telephone/AccountWindowView.swift"
            ),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Telephone/AccountController.swift"
            ),
            encoding: .utf8
        )

        let session = AccountSession()
        session.transition(to: .connectionLost)
        #expect(session.state == .connectionLost)
        session.transition(to: .unavailable)
        #expect(session.state == .unavailable)
        #expect(viewSource.contains("\"Connection Lost\""))
        #expect(
            viewSource.contains(
                "exclamationmark.triangle.fill"
            )
        )
        #expect(controllerSource.contains("else if accountUnavailable"))
        #expect(controllerSource.contains("showConnectionLostState()"))
        #expect(
            controllerSource.contains(
                "case .unavailable:\n            accountUnavailable = true"
            )
        )
    }

    @Test
    func sipRegistrationUsesPJSIPExpirySentinel() throws {
        let accountSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Telephone/AKSIPAccount.swift"
            ),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Telephone/AccountController.swift"
            ),
            encoding: .utf8
        )

        let sentinel =
            "kAKSIPAccountRegistrationExpireTimeNotSpecified"

        #expect(accountSource.contains("PJSIP_EXPIRES_NOT_SPECIFIED"))
        #expect(!accountSource.contains("registrationExpireTime != -1"))
        #expect(!controllerSource.contains("registrationExpireTime == -1"))
        #expect(
            controllerSource.components(separatedBy: sentinel).count - 1 == 2
        )
    }

    @Test
    func crmHistorySheetUsesSingleScrollableResultRegion() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Telephone/CRMHistoryLookupView.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains(".frame(minHeight: 160, idealHeight: 320)"))
        #expect(source.contains("minHeight: 420, idealHeight: 560"))
        #expect(
            source.components(separatedBy: "ScrollView {").count - 1 == 1
        )
    }

    @Test
    func systemMediaPauseDoesNotReadNowPlayingState() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Telephone/SystemMediaPlayer.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("MRMediaRemoteSendCommand"))
        #expect(
            !source.contains(
                "MRMediaRemoteGetNowPlayingApplicationIsPlaying"
            )
        )
    }

    @Test
    func appMenuUsesNativeSettingsSceneOnly() throws {
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Telephone/TelephoneApp.swift"
            ),
            encoding: .utf8
        )
        let preferencesSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Telephone/PreferencesController.swift"
            ),
            encoding: .utf8
        )

        #expect(!appSource.contains("CommandGroup(replacing: .appSettings)"))
        #expect(!appSource.contains("\"Settings…\""))
        #expect(preferencesSource.contains("Settings {"))
    }

    @Test
    func accountToolbarKeepsCompactStatusFallback() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Telephone/AccountWindowView.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("expandedStateMinimumWidth: CGFloat = 370"))
        #expect(source.contains("AccountStateIndicator(state: state)"))
        #expect(source.contains("if showsTitle"))
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
