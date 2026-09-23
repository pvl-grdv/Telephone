//
//  CallWindowScene.swift
//  Telephone
//

import AppKit
import SwiftUI

@MainActor
enum CallPresentationRegistry {
    static let shared =
        WeakObjectRegistry<String, CallPresentationCoordinator>()
}

private struct CallWindowsScene: Scene {
    @AppStorage(UserDefaultsKeys.keepCallWindowOnTop)
    private var keepOnTop = false

    var body: some Scene {
        WindowGroup(
            NSLocalizedString(
                "Call",
                comment: "Call window scene title."
            ),
            id: CallWindowSceneController.sceneID,
            for: String.self
        ) { key in
            if let key = key.wrappedValue,
               let presentation = CallPresentationRegistry.shared.value(
                   for: key
               ) {
                presentation.contentView
            } else {
                EmptyView()
            }
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowBackgroundDragBehavior(.enabled)
        .windowLevel(keepOnTop ? .floating : .normal)
    }
}

@MainActor
final class CallWindowSceneController {
    static let shared = CallWindowSceneController()
    static let sceneID = "telephone-call"

    private let representation = NSHostingSceneRepresentation {
        CallWindowsScene()
    }
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        NSApplication.shared.addSceneRepresentation(representation)
    }

    func show(key: String) {
        install()
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
