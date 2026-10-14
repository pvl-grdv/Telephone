//
//  CallControlViews.swift
//  Telephone
//

import Foundation
import SwiftUI

struct IncomingCallSection: View {
    let model: CallWindowModel
    @FocusState private var focusedAction: Action?

    let answer: () -> Void
    let decline: () -> Void

    private enum Action: Hashable {
        case answer
        case decline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CallIdentityView(
                displayedName: model.displayedName,
                identityDetail: model.identityDetail,
                status: model.status,
                usesDTMFDisplay: false
            )

            HStack(spacing: 12) {
                Spacer(minLength: 0)

                Button(action: decline) {
                    Label(
                        NSLocalizedString("Decline", comment: "Call decline button."),
                        systemImage: "phone.down.fill"
                    )
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("call.decline")
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
                .accessibilityIdentifier("call.answer")
                .focused($focusedAction, equals: .answer)
                .disabled(!model.incomingActionsEnabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .defaultFocus($focusedAction, .answer)
        .onChange(of: model.answerFocusRequest) {
            focusedAction = .answer
        }
    }
}

struct ActiveCallSection: View {
    let model: CallWindowModel

    let hangUp: () -> Void
    let toggleMute: () -> Void
    let toggleHold: () -> Void
    let showTransfer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CallIdentityView(
                displayedName: model.displayedName,
                identityDetail: model.identityDetail,
                status: model.status,
                usesDTMFDisplay: model.usesDTMFDisplay
            )

            HStack(spacing: 8) {
                if model.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(action: hangUp) {
                    Image(systemName: "phone.down.fill")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(!model.hangUpEnabled)
                .help(NSLocalizedString("End Call", comment: "End call button."))
                .accessibilityIdentifier("call.end")
                .accessibilityLabel(
                    NSLocalizedString("End Call", comment: "End call button.")
                )

                Spacer(minLength: 8)

                CallControlButton(
                    systemImage: model.muted ? "mic.slash.fill" : "mic.fill",
                    help: model.muted
                        ? NSLocalizedString("Unmute", comment: "Unmute. Call menu item.")
                        : NSLocalizedString("Mute", comment: "Mute. Call menu item."),
                    isEnabled: model.muteEnabled,
                    accessibilityIdentifier: "call.mute",
                    action: toggleMute
                )

                CallControlButton(
                    systemImage: model.held ? "play.fill" : "pause.fill",
                    help: model.held
                        ? NSLocalizedString("Resume", comment: "Resume. Call menu item.")
                        : NSLocalizedString("Hold", comment: "Hold. Call menu item."),
                    isEnabled: model.holdEnabled,
                    accessibilityIdentifier: "call.hold",
                    action: toggleHold
                )

                CallControlButton(
                    systemImage: "arrow.right",
                    help: NSLocalizedString(
                        "Transfer",
                        comment: "Transfer. Call menu item."
                    ),
                    isEnabled: model.transferEnabled,
                    accessibilityIdentifier: "call.transfer",
                    action: showTransfer
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EndedCallSection: View {
    let model: CallWindowModel
    let redial: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CallIdentityView(
                displayedName: model.displayedName,
                identityDetail: model.identityDetail,
                status: model.status,
                usesDTMFDisplay: false
            )

            HStack {
                Spacer(minLength: 0)

                Button(action: redial) {
                    Label(
                        NSLocalizedString("Call Back", comment: "Call back button."),
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.redialEnabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CallIdentityView: View {
    let displayedName: String
    let identityDetail: String
    let status: String
    let usesDTMFDisplay: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(displayedName)
                .font(.headline)
                .lineLimit(usesDTMFDisplay ? 1 : 2)
                .truncationMode(usesDTMFDisplay ? .head : .tail)
                .fixedSize(horizontal: false, vertical: true)
                .help(displayedName)

            if !identityDetail.isEmpty {
                Text(identityDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(identityDetail)
            }

            Text(status)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CallControlButton: View {
    let systemImage: String
    let help: String
    let isEnabled: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.bordered)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(help)
    }
}
