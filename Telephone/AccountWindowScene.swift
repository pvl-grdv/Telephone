//
//  AccountWindowScene.swift
//  Telephone
//

import AppKit
import SwiftUI

@MainActor
enum AccountPresentationRegistry {
    static let shared =
        WeakObjectRegistry<String, AccountPresentationCoordinator>()
}

private struct AccountWindowsScene: Scene {
    var body: some Scene {
        WindowGroup(
            NSLocalizedString(
                "Account",
                comment: "Account window scene title."
            ),
            id: AccountWindowSceneController.sceneID,
            for: String.self
        ) { key in
            AccountWindowSceneContent(key: key.wrappedValue)
        }
        .defaultLaunchBehavior(.suppressed)
    }
}

private struct AccountWindowSceneContent: View {
    @State private var registry = AccountPresentationRegistry.shared

    let key: String?

    var body: some View {
        let _ = registry.generation

        if let key,
           let controller = registry.value(for: key) {
            controller.contentView
        } else {
            EmptyView()
        }
    }
}

@MainActor
final class AccountWindowSceneController {
    static let shared = AccountWindowSceneController()
    static let sceneID = "telephone-account"

    private let representation = NSHostingSceneRepresentation {
        AccountWindowsScene()
    }
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        NSApplication.shared.addSceneRepresentation(representation)
    }

    func show(key: String) {
        representation.environment.openWindow(
            id: Self.sceneID,
            value: key
        )
    }

    func hide(key: String) {
        representation.environment.dismissWindow(
            id: Self.sceneID,
            value: key
        )
    }
}
