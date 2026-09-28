//
//  CallWindowScene.swift
//  Telephone
//

import SwiftUI

enum CallWindowScene {
    static let id = "telephone-call"
}

@MainActor
enum CallPresentationRegistry {
    static let shared =
        WeakObjectRegistry<String, CallPresentationCoordinator>()
}

struct CallWindowsScene: Scene {
    @AppStorage(UserDefaultsKeys.keepCallWindowOnTop)
    private var keepOnTop = false

    var body: some Scene {
        WindowGroup(
            NSLocalizedString(
                "Call Window Title",
                comment: "Call window scene title."
            ),
            id: CallWindowScene.id,
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
        .defaultSize(width: 420, height: 120)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .windowIdealSize(.fitToContent)
        .windowBackgroundDragBehavior(.enabled)
        .windowLevel(keepOnTop ? .floating : .normal)
    }
}
