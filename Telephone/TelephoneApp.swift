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
        WindowGroup(
            "Telephone",
            id: "telephone-command-host"
        ) {
            EmptyView()
        }
        .defaultLaunchBehavior(.suppressed)
        .commands {
            AboutTelephoneCommands()

            CommandGroup(replacing: .appSettings) {
                Button(
                    NSLocalizedString(
                        "Settings…",
                        comment: "Application settings menu item."
                    )
                ) {
                    appController.showPreferencesForSwiftUI()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            AccountsCommands(
                model: appController.accountsCommandModelForSwiftUI()
            )

            CallCommands()

            CallHistoryCommands()

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
                        "Open Fork Repository…",
                        comment: "Open maintained fork repository help menu item."
                    )
                ) {
                    appController.openHomepage()
                }

                Button(
                    NSLocalizedString(
                        "Open Original FAQ…",
                        comment: "Open upstream Telephone FAQ help menu item."
                    )
                ) {
                    appController.openFAQ()
                }
            }
        }

        Window(
            NSLocalizedString(
                "About Telephone",
                comment: "About window title."
            ),
            id: AboutTelephoneScene.id
        ) {
            AboutTelephoneView()
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .windowIdealSize(.fitToContent)
        .commandsRemoved()
    }
}
