//
//  AccountSetupPresentationController.swift
//  Telephone
//

import SwiftUI

@MainActor
final class AccountSetupPresentationController {
    class func didAddAccountNotificationName() -> String {
        accountSetupDidAddNotificationName.rawValue
    }

    func showFirstRun() {
        SceneRouter.shared.openWindow(id: AccountSetupScene.id)
    }
}

struct AccountSetupHostedScene: Scene {
    var body: some Scene {
        WindowGroup(
            NSLocalizedString(
                "Account Setup",
                comment: "Account setup window title."
            ),
            id: AccountSetupScene.id
        ) {
            FirstRunAccountSetupView(windowID: AccountSetupScene.id)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 520, height: 360)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .windowIdealSize(.fitToContent)
        .commandsRemoved()
    }
}

enum AccountSetupScene {
    static let id = "telephone-first-run-account-setup"
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
        MacApplication.terminate()
    }

    private func terminateIfAccountWasNotAdded() {
        let accounts = UserDefaults.standard.array(
            forKey: UserDefaultsKeys.accounts
        ) ?? []

        if accounts.isEmpty {
            MacApplication.terminate()
        }
    }
}
