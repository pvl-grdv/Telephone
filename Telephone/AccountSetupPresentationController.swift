//
//  AccountSetupPresentationController.swift
//  Telephone
//

import AppKit
import SwiftUI

@MainActor
@objcMembers
final class AccountSetupPresentationController: NSObject {
    private let controller = AccountSetupSceneController()

    class func didAddAccountNotificationName() -> String {
        accountSetupDidAddNotificationName.rawValue
    }

    func install() {
        controller.install()
    }

    func showFirstRun() {
        controller.show()
    }
}

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

@MainActor
private final class AccountSetupSceneController {
    private static let windowID = "telephone-first-run-account-setup"

    private let representation:
        NSHostingSceneRepresentation<AccountSetupHostedScene>
    private var installed = false

    init() {
        representation = NSHostingSceneRepresentation {
            AccountSetupHostedScene(windowID: Self.windowID)
        }
    }

    func install() {
        guard !installed else { return }
        installed = true
        NSApplication.shared.addSceneRepresentation(representation)
    }

    func show() {
        install()
        representation.environment.openWindow(id: Self.windowID)
    }
}

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
        Task {
            guard await model.saveAccount() else { return }
            dismissWindow(id: windowID)
        }
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
