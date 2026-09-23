//
//  AccountWindowScene.swift
//  Telephone
//

import AppKit
import SwiftUI

@MainActor
final class AccountPresentationRegistry {
    static let shared = AccountPresentationRegistry()

    private final class WeakController {
        weak var value: AccountPresentationCoordinator?

        init(_ value: AccountPresentationCoordinator) {
            self.value = value
        }
    }

    private var controllers: [String: WeakController] = [:]

    func register(_ controller: AccountPresentationCoordinator, key: String) {
        controllers[key] = WeakController(controller)
    }

    func unregister(key: String) {
        controllers.removeValue(forKey: key)
    }

    func controller(for key: String) -> AccountPresentationCoordinator? {
        guard let controller = controllers[key]?.value else {
            controllers[key] = nil
            return nil
        }
        return controller
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
            if let key = key.wrappedValue,
               let controller = AccountPresentationRegistry.shared.controller(for: key) {
                controller.contentView
            } else {
                EmptyView()
            }
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
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
