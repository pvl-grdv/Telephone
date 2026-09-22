//
//  TelephoneApp.swift
//  Telephone
//

import SwiftUI

@main
struct TelephoneApp: App {
    @NSApplicationDelegateAdaptor(AppController.self)
    private var appController

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(
                    NSLocalizedString(
                        "Settings…",
                        comment: "Application settings menu item."
                    )
                ) {
                    appController.showPreferencePanel(nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
