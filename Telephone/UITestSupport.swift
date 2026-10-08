//
//  UITestSupport.swift
//  Telephone
//

import Foundation
import SwiftUI

@MainActor
enum TelephoneUITestSupport {
    static func handleLaunch(
        coordinator: ApplicationCoordinator
    ) -> Bool {
#if DEBUG
        guard
            let scenario = ProcessInfo.processInfo.environment[
                "TELEPHONE_UI_TEST_SCENARIO"
            ]
        else {
            return false
        }

        resetDefaults()

        guard
            scenario == "settings"
                || scenario == "account-setup"
                || scenario == "incoming-call"
                || scenario == "incoming-call-details"
        else {
            return false
        }

        Task { @MainActor in
            await Task.yield()

            switch scenario {
            case "settings":
                coordinator.showPreferencesForUITesting()
            case "account-setup":
                coordinator.showAccountSetupForUITesting()
            case "incoming-call", "incoming-call-details":
                if scenario != "incoming-call" {
                    UserDefaults.standard.set(true, forKey: UserDefaultsKeys.showCustomerContext)
                }
                await UITestCallSceneController.shared.show(includeCRM: scenario == "incoming-call-details")
            default:
                break
            }

            MacApplication.activate()
        }

        return true
#else
        return false
#endif
    }

#if DEBUG
    private static func resetDefaults() {
        let defaults = UserDefaults.standard

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        }

        defaults.set(
            SettingsSection.general.rawValue,
            forKey: UserDefaultsKeys.settingsSection
        )
        defaults.set(
            false,
            forKey: UserDefaultsKeys.showCustomerContext
        )
    }
#endif
}

#if DEBUG

@MainActor
struct UITestCallHostedScene: Scene {
    var body: some Scene {
        Window(
            NSLocalizedString(
                "Call Window Title",
                comment: "UI test call window title."
            ),
            id: UITestCallSceneController.sceneID
        ) {
            UITestIncomingCallView()
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 420, height: 120)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .windowIdealSize(.fitToContent)
        .commandsRemoved()
    }
}

@MainActor
private final class UITestCallSceneController {
    static let shared = UITestCallSceneController()
    static let sceneID = "telephone-ui-test-call"

    private(set) var crmKeyLookupModel: CRMKeyLookupModel?

    func show(includeCRM: Bool) async {
        crmKeyLookupModel = nil
        if includeCRM {
            // A private synthetic provider and token store; never use saved
            // account settings, Keychain credentials, SIP, or a real gateway.
            let defaults = UserDefaults(suiteName: "Telephone.UITestCRM.\(UUID())")!
            let settings = CRMGatewaySettings(defaults: defaults, tokenStore: UITestCRMTokenStore())
            do {
                try await settings.save(enabled: true, origin: "https://gateway.example", newToken: "synthetic-token")
                let lookup = CRMKeyLookupModel(settings: settings, provider: UITestCRMProvider())
                lookup.setCallerPhone("+12025550100", isActive: true)
                crmKeyLookupModel = lookup
            } catch {
                assertionFailure("Could not configure synthetic CRM fixture: \(error)")
            }
        }
        SceneRouter.shared.openWindow(id: Self.sceneID)
    }
}

@MainActor
private struct UITestIncomingCallView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var model = CallWindowModel(isTransfer: false)
    @State private var configured = false
    @State private var customerDetailsWindow: CallCustomerDetailsWindowController?

    private var crmKeyLookupModel: CRMKeyLookupModel? {
        UITestCallSceneController.shared.crmKeyLookupModel
    }

    var body: some View {
        CallWindowView(
            model: model,
            transferDestinationComposer: nil,
            crmKeyLookupModel: crmKeyLookupModel,
            answer: answer,
            decline: close,
            hangUp: close,
            toggleMute: {
                model.muted.toggle()
            },
            toggleHold: {
                model.held.toggle()
            },
            showTransfer: {},
            redial: {},
            callTransferDestination: {},
            closeTransfer: {},
            cancelTransfer: {},
            completeTransfer: {},
            showCustomerDetails: showCustomerDetails,
            customerContextVisibilityChanged: { _ in },
            sendDTMF: { _ in }
        )
        .onAppear {
            configureIncomingCallIfNeeded()
        }
    }

    private func configureIncomingCallIfNeeded() {
        guard !configured else { return }
        configured = true

        model.customerContextLoaded = true
        model.displayedName = "Ada Lovelace"
        model.identityDetail = "+1 202 555 0100"
        model.status = NSLocalizedString(
            "calling",
            comment: "Incoming call status for UI tests."
        )
        model.windowTitle = NSLocalizedString(
            "Incoming Call",
            comment: "Incoming call window title."
        )
        model.showIncomingState()
        model.answerFocusRequest &+= 1
    }

    private func answer() {
        model.windowTitle = NSLocalizedString(
            "Call Window Title",
            comment: "Active call window title."
        )
        model.status = "00:00"
        model.showActiveState()
        model.muteEnabled = true
        model.holdEnabled = true
        model.transferEnabled = true
        model.requestCallSurfaceFocus()
    }

    private func showCustomerDetails() {
        if customerDetailsWindow == nil {
            customerDetailsWindow = CallCustomerDetailsWindowController(
                model: model, crmKeyLookupModel: crmKeyLookupModel, changed: {}, reload: {}, save: {}, saveOnClose: {}
            )
        }
        customerDetailsWindow?.present()
    }

    private func close() {
        customerDetailsWindow?.close()
        customerDetailsWindow = nil
        dismissWindow(id: UITestCallSceneController.sceneID)
    }
}

/// Deterministic, in-memory CRM data for the actual hosted-window UI smoke test.
private struct UITestCRMProvider: CRMKeyLookupProvider {
    func customer(forKeyNumber keyNumber: Int, configuration: CRMGatewayConfiguration) async throws -> CRMKeyLookupResponse {
        try JSONDecoder().decode(CRMKeyLookupResponse.self, from: Self.response)
    }

    func customer(forPhoneNumber phoneNumber: String, companyID: Int?, configuration: CRMGatewayConfiguration) async throws -> CRMPhoneLookupResponse {
        try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: Self.response)
    }

    func customer(forEmail email: String, companyID: Int?, configuration: CRMGatewayConfiguration) async throws -> CRMPhoneLookupResponse {
        try JSONDecoder().decode(CRMPhoneLookupResponse.self, from: Self.response)
    }

    private static let response = Data("""
    {"data":{"sourceKeyId":1,"company":{"id":7000,"name":"Synthetic Organization","formattedCode":"00-00-7000","phone":"+12025550100","phones":["+12025550100"]},"keys":[{"id":1,"name":"Synthetic key","url":"https://example.test/keys/1","programs":[{"recordId":1,"programId":1,"name":"Synthetic Air","version":"1.0","release":"0010","keyUrl":"https://example.test/keys/1"}]}]},"matches":[],"meta":{"requestId":"synthetic-ui","fetchedAt":"2026-10-08T08:00:00Z","complete":true,"fromCache":false}}
    """.utf8)
}

private actor UITestCRMTokenStore: CRMGatewayTokenStoring {
    func token(for origin: String) -> String { "synthetic-token" }
    func save(_ token: String, for origin: String) -> Bool { true }
    func remove(for origin: String) -> Bool { true }
}

#endif
