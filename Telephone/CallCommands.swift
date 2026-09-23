//
//  CallMenuInstaller.swift
//  Telephone
//

import SwiftUI

extension FocusedValues {
    @Entry var callCommandTarget: CallPresentationCoordinator?
}

struct CallCommands: Commands {
    @FocusedValue(\.callCommandState) private var state
    @FocusedValue(\.callCommandTarget) private var target
    @AppStorage(UserDefaultsKeys.keepCallWindowOnTop)
    private var keepOnTop = false

    var body: some Commands {
        CommandMenu(
            NSLocalizedString(
                "Call",
                comment: "Call menu title."
            )
        ) {
            commandButton(
                title: state?.muted == true
                    ? NSLocalizedString(
                        "Unmute",
                        comment: "Unmute. Call menu item."
                    )
                    : NSLocalizedString(
                        "Mute",
                        comment: "Mute. Call menu item."
                    ),
                action: { target?.toggleMicrophoneMute() },
                enabled: state?.phase == .active
                    && state?.muteEnabled == true,
                key: "m",
                modifiers: [.command, .shift]
            )

            commandButton(
                title: state?.held == true
                    ? NSLocalizedString(
                        "Resume",
                        comment: "Resume. Call menu item."
                    )
                    : NSLocalizedString(
                        "Hold",
                        comment: "Hold. Call menu item."
                    ),
                action: { target?.toggleCallHold() },
                enabled: holdEnabled
            )

            commandButton(
                title: NSLocalizedString(
                    "Transfer",
                    comment: "Transfer. Call menu item."
                ),
                action: { target?.showCallTransfer() },
                enabled: state?.phase == .active
                    && state?.transferEnabled == true
            )

            commandButton(
                title: NSLocalizedString(
                    "Call Back",
                    comment: "Call back menu item."
                ),
                action: { target?.redial() },
                enabled: redialEnabled,
                key: "r"
            )

            Divider()

            commandButton(
                title: NSLocalizedString(
                    "Answer",
                    comment: "Call answer menu item."
                ),
                action: { target?.acceptCall() },
                enabled: state?.phase == .incoming
                    && state?.incomingActionsEnabled == true,
                key: "\r",
                modifiers: []
            )

            commandButton(
                title: state?.phase == .incoming
                    ? NSLocalizedString(
                        "Decline",
                        comment: "Decline. Call menu item."
                    )
                    : NSLocalizedString(
                        "End Call",
                        comment: "End call menu item."
                    ),
                action: { target?.hangUpCall() },
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
    private func commandButton(
        title: String,
        action: @escaping () -> Void,
        enabled: Bool,
        key: KeyEquivalent? = nil,
        modifiers: EventModifiers = .command
    ) -> some View {
        let button = Button(title, action: action)
            .disabled(!enabled || target == nil)

        if let key {
            button.keyboardShortcut(key, modifiers: modifiers)
        } else {
            button
        }
    }
}
