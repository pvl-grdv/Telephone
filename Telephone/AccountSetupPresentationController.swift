//
//  AccountSetupPresentationController.swift
//  Telephone
//

import AppKit
import SwiftUI

@MainActor
@objcMembers
final class AccountSetupPresentationController: NSObject {
    private lazy var fallback = AccountSetupController()

    private var modernController: AnyObject?

    class func didAddAccountNotificationName() -> String {
        accountSetupDidAddNotificationName.rawValue
    }

    func install() {
        if #available(macOS 26.0, *) {
            let controller = AccountSetupSceneController()
            modernController = controller
            controller.install()
        }
    }

    func showFirstRun() {
        if #available(macOS 26.0, *),
           let controller = modernController as? AccountSetupSceneController {
            controller.show()
        } else {
            fallback.showCentered()
        }
    }
}

@available(macOS 26.0, *)
private struct AccountSetupHostedScene: Scene {
    let windowID: String

    var body: some Scene {
        WindowGroup(
            NSLocalizedString(
                "Account Setup",
                comment: "Account setup window title."
            ),
            id: windowID
        ) {
            FirstRunAccountSetupView(windowID: windowID)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .commandsRemoved()
    }
}

@available(macOS 26.0, *)
@MainActor
private final class AccountSetupSceneController {
    private static let windowID = "telephone-first-run-account-setup"

    private let representation:
        NSHostingSceneRepresentation<AccountSetupHostedScene>

    init() {
        representation = NSHostingSceneRepresentation {
            AccountSetupHostedScene(windowID: Self.windowID)
        }
    }

    func install() {
        NSApplication.shared.addSceneRepresentation(representation)
    }

    func show() {
        representation.environment.openWindow(id: Self.windowID)
    }
}

@available(macOS 26.0, *)
private struct FirstRunAccountSetupView: View {
    let windowID: String

    @Environment(\.dismissWindow) private var dismissWindow
    @State private var model = AccountSetupModel()

    var body: some View {
        AccountSetupView(
            model: model,
            submit: submit,
            cancel: cancel
        )
        .onAppear {
            model.reset()
        }
        .onDisappear {
            terminateIfAccountWasNotAdded()
        }
    }

    private func submit() {
        guard model.saveAccount() else { return }
        dismissWindow(id: windowID)
    }

    private func cancel() {
        NSApplication.shared.terminate(nil)
    }

    private func terminateIfAccountWasNotAdded() {
        let accounts = UserDefaults.standard.array(
            forKey: UserDefaultsKeys.accounts
        ) ?? []

        if accounts.isEmpty {
            NSApplication.shared.terminate(nil)
        }
    }
}
