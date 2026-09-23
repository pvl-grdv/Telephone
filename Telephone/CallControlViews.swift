//
//  CallControlViews.swift
//  Telephone
//

import Foundation
import SwiftUI

struct IncomingCallSection: View {
    @Bindable var model: CallWindowModel
    @FocusState private var focusedAction: Action?

    let answer: () -> Void
    let decline: () -> Void

    private enum Action: Hashable {
        case answer
        case decline
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            CallIdentityView(
                displayedName: model.displayedName,
                status: model.status,
                usesDTMFDisplay: false
            )

            Spacer(minLength: 12)

            Button(action: decline) {
                Label(
                    NSLocalizedString("Decline", comment: "Call decline button."),
                    systemImage: "phone.down.fill"
                )
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            .focused($focusedAction, equals: .decline)
            .disabled(!model.incomingActionsEnabled)

            Button(action: answer) {
                Label(
                    NSLocalizedString("Answer", comment: "Call answer button."),
                    systemImage: "phone.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .focused($focusedAction, equals: .answer)
            .disabled(!model.incomingActionsEnabled)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .defaultFocus($focusedAction, .answer)
        .onChange(of: model.answerFocusRequest) {
            focusedAction = .answer
        }
    }
}

struct ActiveCallSection: View {
    @Bindable var model: CallWindowModel

    let hangUp: () -> Void
    let toggleMute: () -> Void
    let toggleHold: () -> Void
    let showTransfer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CallIdentityView(
                    displayedName: model.displayedName,
                    status: model.status,
                    usesDTMFDisplay: model.usesDTMFDisplay
                )

                Spacer(minLength: 8)

                if model.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(action: hangUp) {
                    Image(systemName: "phone.down.fill")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .disabled(!model.hangUpEnabled)
                .help(NSLocalizedString("End Call", comment: "End call button."))
                .accessibilityLabel(
                    NSLocalizedString("End Call", comment: "End call button.")
                )
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                CallControlButton(
                    systemImage: model.muted ? "mic.slash.fill" : "mic.fill",
                    help: model.muted
                        ? NSLocalizedString("Unmute", comment: "Unmute. Call menu item.")
                        : NSLocalizedString("Mute", comment: "Mute. Call menu item."),
                    isEnabled: model.muteEnabled,
                    action: toggleMute
                )

                CallControlButton(
                    systemImage: model.held ? "play.fill" : "pause.fill",
                    help: model.held
                        ? NSLocalizedString("Resume", comment: "Resume. Call menu item.")
                        : NSLocalizedString("Hold", comment: "Hold. Call menu item."),
                    isEnabled: model.holdEnabled,
                    action: toggleHold
                )

                CallControlButton(
                    systemImage: "arrow.right",
                    help: NSLocalizedString(
                        "Transfer",
                        comment: "Transfer. Call menu item."
                    ),
                    isEnabled: model.transferEnabled,
                    action: showTransfer
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54)
    }
}

struct EndedCallSection: View {
    @Bindable var model: CallWindowModel
    let redial: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            CallIdentityView(
                displayedName: model.displayedName,
                status: model.status,
                usesDTMFDisplay: false
            )

            Spacer(minLength: 12)

            Button(action: redial) {
                Label(
                    NSLocalizedString("Call Back", comment: "Call back button."),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.redialEnabled)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
    }
}

struct CallIdentityView: View {
    let displayedName: String
    let status: String
    let usesDTMFDisplay: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayedName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(usesDTMFDisplay ? .head : .tail)

            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct CallControlButton: View {
    let systemImage: String
    let help: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.bordered)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(help)
    }
}
