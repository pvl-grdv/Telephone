//
//  CallWindowScene.swift
//  Telephone
//

import AppKit
import SwiftUI

@MainActor
final class CallPresentationRegistry {
    static let shared = CallPresentationRegistry()

    private final class WeakPresentation {
        weak var value: CallPresentationCoordinator?

        init(_ value: CallPresentationCoordinator) {
            self.value = value
        }
    }

    private var presentations: [String: WeakPresentation] = [:]

    func register(_ presentation: CallPresentationCoordinator) {
        presentations[presentation.id] = WeakPresentation(presentation)
    }

    func unregister(key: String) {
        presentations.removeValue(forKey: key)
    }

    func presentation(for key: String) -> CallPresentationCoordinator? {
        guard let presentation = presentations[key]?.value else {
            presentations[key] = nil
            return nil
        }
        return presentation
    }
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
               let presentation = CallPresentationRegistry.shared.presentation(
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
