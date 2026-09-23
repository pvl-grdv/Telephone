//
//  CallMenuInstaller.swift
//  Telephone
//

import AppKit
import SwiftUI

struct CallCommands: Commands {
    private let defaults = UserDefaults.standard

    var body: some Commands {
        CommandMenu(
            NSLocalizedString(
                "Call",
                comment: "Call menu title."
            )
        ) {
            responderButton(
                title: NSLocalizedString(
                    "Mute",
                    comment: "Mute. Call menu item."
                ),
                selector: Selector(("toggleMicrophoneMute:")),
                key: "m",
                modifiers: [.command, .shift]
            )

            responderButton(
                title: NSLocalizedString(
                    "Hold",
                    comment: "Hold. Call menu item."
                ),
                selector: Selector(("toggleCallHold:"))
            )

            responderButton(
                title: NSLocalizedString(
                    "Transfer",
                    comment: "Transfer. Call menu item."
                ),
                selector: Selector(("showCallTransferSheet:"))
            )

            responderButton(
                title: NSLocalizedString(
                    "Call Back",
                    comment: "Call back menu item."
                ),
                selector: Selector(("redial:")),
                key: "r"
            )

            Divider()

            responderButton(
                title: NSLocalizedString(
                    "Answer",
                    comment: "Call answer menu item."
                ),
                selector: Selector(("acceptCall:")),
                key: "\r",
                modifiers: []
            )

            responderButton(
                title: NSLocalizedString(
                    "End Call",
                    comment: "End call menu item."
                ),
                selector: Selector(("hangUpCall:")),
                key: "."
            )

            Divider()

            Toggle(
                NSLocalizedString(
                    "Keep on Top",
                    comment: "Keep call window on top menu item."
                ),
                isOn: Binding(
                    get: {
                        defaults.bool(
                            forKey: UserDefaultsKeys.keepCallWindowOnTop
                        )
                    },
                    set: { newValue in
                        defaults.set(
                            newValue,
                            forKey: UserDefaultsKeys.keepCallWindowOnTop
                        )
                    }
                )
            )
        }
    }

    @ViewBuilder
    private func responderButton(
        title: String,
        selector: Selector,
        key: KeyEquivalent? = nil,
        modifiers: EventModifiers = .command
    ) -> some View {
        let button = Button(title) {
            NSApp.sendAction(
                selector,
                to: nil,
                from: nil
            )
        }
        .disabled(
            NSApp.target(
                forAction: selector,
                to: nil,
                from: nil
            ) == nil
        )

        if let key {
            button.keyboardShortcut(key, modifiers: modifiers)
        } else {
            button
        }
    }
}
