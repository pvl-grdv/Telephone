//
//  CallDestinationComposer.swift
//  Telephone
//

import Foundation
import SwiftUI

@MainActor
final class CallDestinationComposer {
    private weak var accountController: AccountController?
    private let inputModel = CallDestinationInputModel()

    var callDestinationURI: AKSIPURI? {
        inputModel.callDestinationURI
    }

    var callDestinationPhoneLabel: String {
        inputModel.callDestinationPhoneLabel
    }

    var contentView: some View {
        inputView(
            showsCallButton: true,
            call: { [weak self] in
                self?.makeCall()
            }
        )
    }

    init(accountController: AccountController) {
        self.accountController = accountController
    }

    func makeCall(callTransferController: CallTransferController? = nil) {
        guard let uri = callDestinationURI else { return }

        if let callTransferController {
            accountController?.makeCall(
                to: uri,
                phoneLabel: callDestinationPhoneLabel,
                callTransferController: callTransferController
            )
        } else {
            accountController?.makeCall(
                to: uri,
                phoneLabel: callDestinationPhoneLabel
            )
        }
    }

    func makeCallToDestination(_ destination: String) {
        inputModel.setDestination(destination)
        makeCall()
    }

    func focus() {
        inputModel.requestFocus()
    }

    func inputView(
        showsCallButton: Bool,
        call: @escaping () -> Void
    ) -> some View {
        CallDestinationInputView(
            model: inputModel,
            showsCallButton: showsCallButton,
            call: call
        )
    }
}

private struct CallDestinationInputView: View {
    @Bindable var model: CallDestinationInputModel
    @FocusState private var inputFocused: Bool

    let showsCallButton: Bool
    let call: () -> Void

    private var showsSuggestions: Bool {
        inputFocused && !model.suggestions.isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            inputRow

            if showsSuggestions {
                DestinationSuggestionsView(
                    suggestions: model.suggestions,
                    highlightedID: model.highlightedSuggestionID,
                    choose: model.chooseSuggestion,
                    hover: model.highlightSuggestion
                )
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .defaultFocus($inputFocused, true)
        .onDisappear {
            model.setFocused(false)
        }
        .onChange(of: inputFocused) {
            model.setFocused(inputFocused)
        }
        .onChange(of: model.focusRequest) {
            inputFocused = true
        }
        .animation(.easeInOut(duration: 0.12), value: showsSuggestions)
    }

    private var inputRow: some View {
        HStack(spacing: 6) {
            TextField(
                NSLocalizedString(
                    "Phone number or SIP address",
                    comment: "Call destination field placeholder."
                ),
                text: $model.text
            )
            .textFieldStyle(.roundedBorder)
            .focused($inputFocused)
            .onSubmit {
                if !model.acceptHighlightedSuggestion() {
                    call()
                }
            }
            .onKeyPress(.downArrow) {
                model.moveSuggestionSelection(by: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                model.moveSuggestionSelection(by: -1)
                return .handled
            }
            .onKeyPress(.escape) {
                model.dismissSuggestions()
                return .handled
            }

            if model.hasMultipleDestinations {
                Menu {
                    ForEach(model.destinationOptions) { option in
                        Button {
                            model.selectDestination(at: option.id)
                        } label: {
                            if option.isSelected {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help(
                    NSLocalizedString(
                        "Choose Destination",
                        comment: "Choose a contact destination."
                    )
                )
                .accessibilityLabel(
                    NSLocalizedString(
                        "Choose Destination",
                        comment: "Choose a contact destination."
                    )
                )
            }

            if showsCallButton {
                if model.canCall {
                    callButton.buttonStyle(.borderedProminent)
                } else {
                    callButton.buttonStyle(.bordered)
                }
            }
        }
    }

    private var callButton: some View {
        Button(action: call) {
            Image(systemName: "phone.fill")
        }
        .controlSize(.small)
        .disabled(!model.canCall)
        .help(NSLocalizedString("Call", comment: "Call button."))
        .accessibilityLabel(
            NSLocalizedString("Call", comment: "Call button.")
        )
    }
}

private struct DestinationSuggestionsView: View {
    let suggestions: [CallDestinationSuggestion]
    let highlightedID: String?
    let choose: (CallDestinationSuggestion) -> Void
    let hover: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    choose(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.title)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Text(suggestion.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .background {
                        if highlightedID == suggestion.id {
                            Color.accentColor.opacity(0.12)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        hover(suggestion.id)
                    }
                }

                if suggestion.id != suggestions.last?.id {
                    Divider()
                        .padding(.leading, 38)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(.separator.opacity(0.6), lineWidth: 0.5)
        }
        .shadow(radius: 5, y: 2)
    }
}


struct TransferDestinationView: View {
    let composer: CallDestinationComposer
    let call: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                NSLocalizedString(
                    "Transfer to:",
                    comment: "Call transfer destination label."
                )
            )
            .font(.headline)

            composer.inputView(
                showsCallButton: false,
                call: call
            )

            HStack {
                Spacer()

                Button(
                    NSLocalizedString("Close", comment: "Close button."),
                    action: close
                )
                .keyboardShortcut(.cancelAction)

                Button(
                    NSLocalizedString("Call", comment: "Call button."),
                    action: call
                )
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 320, idealWidth: 360, minHeight: 118)
    }
}
