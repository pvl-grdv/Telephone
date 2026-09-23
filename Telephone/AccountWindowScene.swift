//
//  AccountWindowScene.swift
//  Telephone
//

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AccountPresentationRegistry {
    static let shared = AccountPresentationRegistry()

    private final class WeakController {
        weak var value: AccountPresentationCoordinator?

        init(_ value: AccountPresentationCoordinator) {
            self.value = value
        }
    }

    @ObservationIgnored
    private var controllers: [String: WeakController] = [:]

    private(set) var generation = 0

    func register(_ controller: AccountPresentationCoordinator, key: String) {
        controllers[key] = WeakController(controller)
        generation &+= 1
    }

    func unregister(key: String) {
        controllers.removeValue(forKey: key)
        generation &+= 1
    }

    func controller(for key: String) -> AccountPresentationCoordinator? {
        controllers[key]?.value
    }
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
           let controller = registry.controller(for: key) {
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
