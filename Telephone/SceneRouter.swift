//
//  SceneRouter.swift
//  Telephone
//

import SwiftUI

@MainActor
final class SceneRouter {
    static let shared = SceneRouter()

    private var openWindowAction: OpenWindowAction?
    private var dismissWindowAction: DismissWindowAction?
    private var openSettingsAction: OpenSettingsAction?

    private init() {}

    func configure(
        openWindow: OpenWindowAction,
        dismissWindow: DismissWindowAction,
        openSettings: OpenSettingsAction
    ) {
        openWindowAction = openWindow
        dismissWindowAction = dismissWindow
        openSettingsAction = openSettings
    }

    func openWindow(id: String) {
        openWindowAction?(id: id)
    }

    func openWindow(id: String, value: String) {
        openWindowAction?(id: id, value: value)
    }

    func dismissWindow(id: String) {
        dismissWindowAction?(id: id)
    }

    func dismissWindow(id: String, value: String) {
        dismissWindowAction?(id: id, value: value)
    }

    func openSettings() {
        openSettingsAction?()
    }
}
