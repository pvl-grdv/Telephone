//
//  UITestSupport.swift
//  Telephone
//

import AppKit
import SwiftUI

@MainActor
@objcMembers
final class TelephoneUITestSupport: NSObject {
    @objc(handleLaunchWithAppController:)
    static func handleLaunch(appController: AppController) -> Bool {
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
        else {
            return false
        }

        Task { @MainActor in
            await Task.yield()

            switch scenario {
            case "settings":
                appController.showPreferencesForUITesting()
            case "account-setup":
                appController.showAccountSetupForUITesting()
            case "incoming-call":
                UITestCallSceneController.shared.show()
            default:
                break
            }

            NSApplication.shared.activate()
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
private struct UITestCallHostedScene: Scene {
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

    private let representation =
        NSHostingSceneRepresentation<UITestCallHostedScene> {
            UITestCallHostedScene()
        }
    private var installed = false

    func show() {
        if !installed {
            installed = true
            NSApplication.shared.addSceneRepresentation(representation)
        }

        representation.environment.openWindow(id: Self.sceneID)
    }
}

@MainActor
private struct UITestIncomingCallView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var model = CallWindowModel(isTransfer: false)
    @State private var configured = false

    var body: some View {
        CallWindowView(
            model: model,
            transferDestinationComposer: nil,
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
            customerContextChanged: {},
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

    private func close() {
        dismissWindow(id: UITestCallSceneController.sceneID)
    }
}

#endif
