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
            AccountsCommands(
                model: appController.accountsCommandModelForSwiftUI()
                    as! AccountsCommandModel
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
