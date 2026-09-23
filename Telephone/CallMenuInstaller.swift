//
//  CallMenuInstaller.swift
//  Telephone
//

import AppKit
import SwiftUI

struct CallCommands: Commands {
    @FocusedValue(\.callCommandState) private var state
    @AppStorage(UserDefaultsKeys.keepCallWindowOnTop)
    private var keepOnTop = false

    var body: some Commands {
        CommandMenu(
            NSLocalizedString(
                "Call",
                comment: "Call menu title."
            )
        ) {
            responderButton(
                title: state?.muted == true
                    ? NSLocalizedString(
                        "Unmute",
                        comment: "Unmute. Call menu item."
                    )
                    : NSLocalizedString(
                        "Mute",
                        comment: "Mute. Call menu item."
                    ),
                selector: Selector(("toggleMicrophoneMute:")),
                enabled: state?.phase == .active
                    && state?.muteEnabled == true,
                key: "m",
                modifiers: [.command, .shift]
            )

            responderButton(
                title: state?.held == true
                    ? NSLocalizedString(
                        "Resume",
                        comment: "Resume. Call menu item."
                    )
                    : NSLocalizedString(
                        "Hold",
                        comment: "Hold. Call menu item."
                    ),
                selector: Selector(("toggleCallHold:")),
                enabled: holdEnabled
            )

            responderButton(
                title: NSLocalizedString(
                    "Transfer",
                    comment: "Transfer. Call menu item."
                ),
                selector: Selector(("showCallTransferSheet:")),
                enabled: state?.phase == .active
                    && state?.transferEnabled == true
            )

            responderButton(
                title: NSLocalizedString(
                    "Call Back",
                    comment: "Call back menu item."
                ),
                selector: Selector(("redial:")),
                enabled: redialEnabled,
                key: "r"
            )

            Divider()

            responderButton(
                title: NSLocalizedString(
                    "Answer",
                    comment: "Call answer menu item."
                ),
                selector: Selector(("acceptCall:")),
                enabled: state?.phase == .incoming
                    && state?.incomingActionsEnabled == true,
                key: "\r",
                modifiers: []
            )

            responderButton(
                title: state?.phase == .incoming
                    ? NSLocalizedString(
                        "Decline",
                        comment: "Decline. Call menu item."
                    )
                    : NSLocalizedString(
                        "End Call",
                        comment: "End call menu item."
                    ),
                selector: Selector(("hangUpCall:")),
                enabled: hangUpEnabled,
                key: "."
            )

            Divider()

            Toggle(
                NSLocalizedString(
                    "Keep on Top",
                    comment: "Keep call window on top menu item."
                ),
                isOn: $keepOnTop
            )
        }
    }

    private var holdEnabled: Bool {
        guard let state else { return false }
        return (state.phase == .active || state.phase == .transferActive)
            && state.holdEnabled
    }

    private var redialEnabled: Bool {
        guard let state else { return false }
        return (state.phase == .ended || state.phase == .transferEnded)
            && state.redialEnabled
    }

    private var hangUpEnabled: Bool {
        guard let state else { return false }

        switch state.phase {
        case .incoming:
            return state.incomingActionsEnabled
        case .active, .transferActive:
            return state.hangUpEnabled
        default:
            return false
        }
    }

    @ViewBuilder
    private func responderButton(
        title: String,
        selector: Selector,
        enabled: Bool,
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
        .disabled(!enabled)

        if let key {
            button.keyboardShortcut(key, modifiers: modifiers)
        } else {
            button
        }
    }
}
