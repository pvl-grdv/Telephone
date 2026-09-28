//
//  TelephoneApp.swift
//  Telephone
//

import SwiftUI

@main
struct TelephoneApp: App {
    @NSApplicationDelegateAdaptor(MacApplicationDelegate.self)
    private var appController

    @Environment(\.openWindow)
    private var openWindow

    @Environment(\.dismissWindow)
    private var dismissWindow

    @Environment(\.openSettings)
    private var openSettings

    var body: some Scene {
        let _ = SceneRouter.shared.configure(
            openWindow: openWindow,
            dismissWindow: dismissWindow,
            openSettings: openSettings
        )

        WindowGroup(
            "Telephone",
            id: "telephone-command-host"
        ) {
            EmptyView()
        }
        .defaultLaunchBehavior(.suppressed)
        .commands {
            AboutTelephoneCommands()

            AccountsCommands(
                model: appController.coordinator.accountsCommandModelForSwiftUI()
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
                    appController.coordinator.copySettings()
                }

                Button(
                    NSLocalizedString(
                        "Show Log File in Finder",
                        comment: "Show log file help menu item."
                    )
                ) {
                    appController.coordinator.showLogFile()
                }

                Divider()

                Button(
                    NSLocalizedString(
                        "Open Fork Repository…",
                        comment: "Open maintained fork repository help menu item."
                    )
                ) {
                    appController.coordinator.openHomepage()
                }

                Button(
                    NSLocalizedString(
                        "Open Original FAQ…",
                        comment: "Open upstream Telephone FAQ help menu item."
                    )
                ) {
                    appController.coordinator.openFAQ()
                }
            }
        }

        AccountWindowsScene()

        CallWindowsScene()

        AccountSetupHostedScene()

        ApplicationDialogScene(
            controller:
                appController.coordinator.applicationDialogControllerForSwiftUI()
        )

        PreferencesHostedScene(
            model: appController.coordinator.settingsModelForSwiftUI()
        )

#if DEBUG
        PreferencesUITestHostedScene(
            model: appController.coordinator.settingsModelForSwiftUI()
        )

        UITestCallHostedScene()
#endif

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
