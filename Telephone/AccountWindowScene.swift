//
//  AccountWindowScene.swift
//  Telephone
//

import SwiftUI

enum AccountWindowScene {
    static let id = "telephone-account"
}

@MainActor
enum AccountPresentationRegistry {
    static let shared =
        WeakObjectRegistry<String, AccountPresentationCoordinator>()
}

struct AccountWindowsScene: Scene {
    var body: some Scene {
        WindowGroup(
            NSLocalizedString(
                "Account",
                comment: "Account window scene title."
            ),
            id: AccountWindowScene.id,
            for: String.self
        ) { key in
            AccountWindowSceneContent(key: key.wrappedValue)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 380, height: 300)
        .windowResizability(.contentMinSize)
        .windowIdealSize(.fitToContent)
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
