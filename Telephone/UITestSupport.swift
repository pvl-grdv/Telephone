//
//  UITestSupport.swift
//  Telephone
//

import Foundation
import Observation
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
                || scenario == "call-history"
                || scenario == "crm-workspace"
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
                await UITestCallSceneController.shared.show(includeCRM: scenario == "incoming-call-details")
            case "call-history":
                await UITestHistorySceneController.shared.show()
            case "crm-workspace":
                await UITestCRMSceneController.shared.show()
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
    }
#endif
}

#if DEBUG

@MainActor
struct UITestHistoryHostedScene: Scene {
    var body: some Scene {
        Window("Call History", id: UITestHistorySceneController.sceneID) {
            if let model = UITestHistorySceneController.shared.model {
                CallHistoryScreen(model: model, call: { _ in }, copy: { _ in },
                    deleteRecord: { _ in }, deleteAll: {})
            }
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 660, height: 320)
        .restorationBehavior(.disabled)
        .commandsRemoved()
    }
}

@MainActor
@Observable
private final class UITestHistorySceneController {
    static let shared = UITestHistorySceneController()
    static let sceneID = "telephone-ui-test-history"
    private(set) var model: CallHistoryViewModel?

    func show() async {
        let defaults = UserDefaults(suiteName: "Telephone.UITestHistory.\(UUID())")!
        let settings = CRMGatewaySettings(defaults: defaults, tokenStore: UITestCRMTokenStore())
        do {
            try await settings.save(enabled: true, origin: "https://gateway.example", newToken: "synthetic-token")
            let history = CallHistoryViewModel(gatewaySettings: settings, answerProvider: UITestHistoryAnswerProvider())
            history.show(["answered", "unanswered", "unknown"].enumerated().map { index, status in
                PresentationCallHistoryRecord(identifier: status,
                    contact: PresentationContact(title: "Synthetic \(status)", tooltip: "", label: "", address: "+1202555010\(index)"),
                    date: "Today, 12:00", duration: "00:00", isIncoming: true, isMissed: true,
                    startedAt: Date(timeIntervalSince1970: 1_791_968_400), callerNumber: "+1202555010\(index)")
            })
            // Visibility and answers are populated by the actual screen lifecycle.
            model = history
            SceneRouter.shared.openWindow(id: Self.sceneID)
        } catch {
            assertionFailure("Could not configure synthetic history fixture: \(error)")
        }
    }
}

private struct UITestHistoryAnswerProvider: CRMCallAnswerProvider {
    func incomingCallAnswers(calls: [CRMIncomingCallRequest], configuration: CRMGatewayConfiguration) async throws -> [CRMIncomingCallAnswer] {
        calls.map { call in
            let status = CRMIncomingCallAnswer.Status(rawValue: call.id) ?? .unknown
            return CRMIncomingCallAnswer(id: call.id, phoneNumber: call.phoneNumber, startedAt: call.startedAt,
                status: status, reason: status == .unknown ? "not-found" : nil,
                answeredBy: status == .answered ? .init(displayName: "Synthetic Employee", source: "ats") : nil,
                match: status == .unknown ? nil : .init(method: "phone-and-time", confidence: "correlated", startedAt: call.startedAt))
        }
    }
}

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
                model.session.muted.toggle()
            },
            toggleHold: {
                model.session.held.toggle()
            },
            showTransfer: {},
            redial: {},
            callTransferDestination: {},
            closeTransfer: {},
            cancelTransfer: {},
            completeTransfer: {},
            showCustomerDetails: showCustomerDetails,
            sendDTMF: { _ in }
        )
        .onAppear {
            configureIncomingCallIfNeeded()
        }
    }

    private func configureIncomingCallIfNeeded() {
        guard !configured else { return }
        configured = true

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
        model.session.muteEnabled = true
        model.session.holdEnabled = true
        model.session.transferEnabled = true
        model.requestCallSurfaceFocus()
    }

    private func showCustomerDetails() {
        guard let crmKeyLookupModel else { return }
        if customerDetailsWindow == nil {
            customerDetailsWindow = CallCustomerDetailsWindowController(
                model: model, crmKeyLookupModel: crmKeyLookupModel
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

@MainActor
struct UITestCRMHostedScene: Scene {
    var body: some Scene {
        Window("CRM", id: UITestCRMSceneController.sceneID) {
            if let model = UITestCRMSceneController.shared.model {
                CRMWorkspaceView(model: model)
            }
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 980, height: 650)
        .restorationBehavior(.disabled)
        .commandsRemoved()
    }
}

@MainActor
@Observable
private final class UITestCRMSceneController {
    static let shared = UITestCRMSceneController()
    static let sceneID = "telephone-ui-test-crm"
    private(set) var model: CRMKeyLookupModel?

    func show() async {
        let defaults = UserDefaults(suiteName: "Telephone.UITestCRMWorkspace.\(UUID())")!
        let settings = CRMGatewaySettings(defaults: defaults, tokenStore: UITestCRMTokenStore())
        do {
            try await settings.save(
                enabled: true, origin: "https://gateway.example", newToken: "synthetic-token"
            )
            model = CRMKeyLookupModel(settings: settings, provider: UITestCRMProvider())
            SceneRouter.shared.openWindow(id: Self.sceneID)
        } catch {
            assertionFailure("Could not configure synthetic CRM workspace: \(error)")
        }
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
