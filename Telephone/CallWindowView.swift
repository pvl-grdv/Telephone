//
//  CallWindowView.swift
//  Telephone
//

import SwiftUI

struct CallWindowView: View {
    @Bindable var model: CallWindowModel

    let transferDestinationComposer: CallDestinationComposer?

    let answer: () -> Void
    let decline: () -> Void
    let hangUp: () -> Void
    let toggleMute: () -> Void
    let toggleHold: () -> Void
    let showTransfer: () -> Void
    let redial: () -> Void
    let callTransferDestination: () -> Void
    let cancelTransfer: () -> Void
    let completeTransfer: () -> Void
    let customerContextChanged: () -> Void

    var body: some View {
        Group {
            if model.isTransfer {
                transferContent
                    .frame(width: 360, height: 160)
            } else {
                regularContent
                    .frame(
                        minWidth: 380,
                        idealWidth: 420,
                        maxWidth: .infinity,
                        minHeight: 280,
                        idealHeight: 318,
                        maxHeight: .infinity
                    )
            }
        }
    }

    private var regularContent: some View {
        VStack(spacing: 0) {
            callStateContent
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            CustomerContextView(
                model: model,
                changed: customerContextChanged
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if model.showsAccountInfo {
                Divider()

                Text(model.accountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(height: 22)
            }
        }
    }

    @ViewBuilder
    private var callStateContent: some View {
        switch model.phase {
        case .incoming:
            IncomingCallSection(
                model: model,
                answer: answer,
                decline: decline
            )
        case .active:
            ActiveCallSection(
                model: model,
                hangUp: hangUp,
                toggleMute: toggleMute,
                toggleHold: toggleHold,
                showTransfer: showTransfer
            )
        case .ended:
            EndedCallSection(
                model: model,
                redial: redial
            )
        case .transferDestination, .transferActive, .transferEnded:
            EmptyView()
        }
    }

    @ViewBuilder
    private var transferContent: some View {
        switch model.phase {
        case .transferDestination:
            if let transferDestinationComposer {
                TransferDestinationView(
                    composer: transferDestinationComposer,
                    call: callTransferDestination,
                    close: cancelTransfer
                )
            }
        case .transferActive:
            TransferActiveSection(
                model: model,
                cancel: cancelTransfer,
                complete: completeTransfer
            )
            .padding(14)
        case .transferEnded:
            TransferEndedSection(
                model: model,
                redial: redial,
                cancel: cancelTransfer
            )
            .padding(14)
        case .incoming, .active, .ended:
            EmptyView()
        }
    }
}

private struct IncomingCallSection: View {
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

private struct ActiveCallSection: View {
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

private struct EndedCallSection: View {
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

private struct TransferActiveSection: View {
    @Bindable var model: CallWindowModel

    let cancel: () -> Void
    let complete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            }

            HStack {
                Spacer()

                Button(
                    NSLocalizedString("Cancel", comment: "Cancel button."),
                    action: cancel
                )
                .keyboardShortcut(.cancelAction)
                .disabled(!model.transferCancelEnabled)

                Button(
                    NSLocalizedString(
                        "Transfer",
                        comment: "Transfer call button."
                    ),
                    action: complete
                )
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.transferActionEnabled)
            }
        }
    }
}

private struct TransferEndedSection: View {
    @Bindable var model: CallWindowModel

    let redial: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CallIdentityView(
                    displayedName: model.displayedName,
                    status: model.status,
                    usesDTMFDisplay: false
                )

                Spacer(minLength: 8)

                Button(action: redial) {
                    Label(
                        NSLocalizedString("Call Back", comment: "Call back button."),
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(!model.redialEnabled)
            }

            HStack {
                Spacer()

                Button(
                    NSLocalizedString("Cancel", comment: "Cancel button."),
                    action: cancel
                )
                .keyboardShortcut(.cancelAction)
            }
        }
    }
}

private struct CallIdentityView: View {
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

private struct CustomerContextView: View {
    @Bindable var model: CallWindowModel
    let changed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(
                    NSLocalizedString(
                        "Client",
                        comment: "Local customer context section title."
                    ),
                    systemImage: "person.crop.circle"
                )
                .font(.caption.weight(.semibold))

                Spacer(minLength: 4)

                if model.customerContextLoaded {
                    Text(historySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            Grid(
                alignment: .leading,
                horizontalSpacing: 8,
                verticalSpacing: 6
            ) {
                customerFieldRow(
                    NSLocalizedString(
                        "Organization",
                        comment: "Local customer organization field placeholder."
                    ),
                    text: $model.customerCompany
                )

                customerFieldRow(
                    NSLocalizedString(
                        "CRM keys",
                        comment: "Local customer CRM keys field placeholder."
                    ),
                    text: $model.customerKeys
                )

                customerFieldRow(
                    NSLocalizedString(
                        "Email addresses",
                        comment: "Local customer email field placeholder."
                    ),
                    text: $model.customerEmails
                )
            }
            .disabled(!model.customerContextLoaded)

            HStack(alignment: .top, spacing: 8) {
                Text(
                    NSLocalizedString(
                        "Notes for this call",
                        comment: "Call note editor placeholder."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .trailing)
                .padding(.top, 5)

                TextEditor(text: $model.customerNote)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(3)
                    .frame(
                        minHeight: 62,
                        idealHeight: 86,
                        maxHeight: .infinity
                    )
                    .background(.background, in: .rect(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(.separator, lineWidth: 0.5)
                    }
                    .disabled(!model.customerContextLoaded)
            }

            if let recent = model.recentCustomerNotes.first {
                Text(
                    String(
                        format: NSLocalizedString(
                            "Previous note: %@",
                            comment: "Most recent previous customer note."
                        ),
                        recent.body
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(recent.body)
            }
        }
        .onChange(of: model.customerCompany) {
            changed()
        }
        .onChange(of: model.customerKeys) {
            changed()
        }
        .onChange(of: model.customerEmails) {
            changed()
        }
        .onChange(of: model.customerNote) {
            changed()
        }
    }

    private func customerFieldRow(
        _ label: String,
        text: Binding<String>
    ) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)

            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var historySummary: String {
        guard model.previousConversationCount > 0 else {
            return NSLocalizedString(
                "No previous conversations",
                comment: "Customer has no previous conversations in Telephone."
            )
        }

        if let lastCallDate = model.lastCallDate {
            let date = lastCallDate.formatted(
                date: .abbreviated,
                time: .omitted
            )
            return String(
                format: NSLocalizedString(
                    "%ld previous · %@",
                    comment: "Previous conversations count and most recent date."
                ),
                model.previousConversationCount,
                date
            )
        }

        return String(
            format: NSLocalizedString(
                "%ld previous conversations",
                comment: "Previous conversations count."
            ),
            model.previousConversationCount
        )
    }
}

private struct CallControlButton: View {
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
