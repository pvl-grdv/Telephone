//
//  TelephoneApp.swift
//  Telephone
//

import AppKit
import SwiftUI

@main
struct TelephoneApp: App {
    @NSApplicationDelegateAdaptor(AppController.self)
    private var appController

    var body: some Scene {
        Settings {
            (appController.preferencesControllerForSwiftUI()
                as! PreferencesController)
                .contentView
        }
        .commands {
            CommandGroup(after: .pasteboard) {
                Button(
                    NSLocalizedString(
                        "Find…",
                        comment: "Focus call history search menu item."
                    )
                ) {
                    NSApp.sendAction(
                        Selector(("focusCallHistorySearch:")),
                        to: nil,
                        from: nil
                    )
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(
                    NSApp.target(
                        forAction: Selector(("focusCallHistorySearch:")),
                        to: nil,
                        from: nil
                    ) == nil
                )
            }

            CommandGroup(after: .help) {
                Divider()

                Button(
                    NSLocalizedString(
                        "Copy Settings",
                        comment: "Copy application settings help menu item."
                    )
                ) {
                    appController.copySettings()
                }

                Button(
                    NSLocalizedString(
                        "Show Log File in Finder",
                        comment: "Show log file help menu item."
                    )
                ) {
                    appController.showLogFile()
                }

                Divider()

                Button(
                    NSLocalizedString(
                        "Open Homepage…",
                        comment: "Open homepage help menu item."
                    )
                ) {
                    appController.openHomepage()
                }

                Button(
                    NSLocalizedString(
                        "Open FAQ…",
                        comment: "Open FAQ help menu item."
                    )
                ) {
                    appController.openFAQ()
                }
            }
        }
    }
}
