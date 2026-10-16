//
//  CallHistoryScreen.swift
//  Telephone
//

import SwiftUI

struct CallHistoryScreen: View {
    let model: CallHistoryViewModel

    let call: (String) -> Void
    let copy: (String) -> Void
    let deleteRecord: (String) -> Void
    let deleteAll: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CallHistoryControls(model: model)
            Divider()
            CallHistoryResults(model: model, call: call, copy: copy)
        }
        .alert(
            model.pendingDeletion?.title ?? "",
            isPresented: deletionIsPresented
        ) {
            Button(
                NSLocalizedString("Delete", comment: "Delete button."),
                role: .destructive
            ) {
                model.commitPendingDeletion(
                    deleteRecord: deleteRecord,
                    deleteAll: deleteAll
                )
            }
            Button(
                NSLocalizedString("Cancel", comment: "Cancel button."),
                role: .cancel
            ) {
                model.pendingDeletion = nil
            }
        } message: {
            Text(
                NSLocalizedString(
                    "This action cannot be undone.",
                    comment:
                        "Call history record removal alert informative text."
                )
            )
        }
    }

    private var deletionIsPresented: Binding<Bool> {
        Binding(
            get: { model.pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    model.pendingDeletion = nil
                }
            }
        )
    }
}

private struct CallHistoryControls: View {
    @Bindable var model: CallHistoryViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        let canRefreshAnswers = !model.answerContext.calls.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                CallHistoryFilterMenu(selection: $model.filter)

                TextField(
                    NSLocalizedString(
                        "Search Call History",
                        comment: "Call history search field placeholder."
                    ),
                    text: $model.query
                )
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)

                if canRefreshAnswers {
                    Button {
                        model.answerRefreshRequest &+= 1
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .frame(width: 28, height: 26)
                    .help(NSLocalizedString("Refresh Call Answers", comment: "Refresh answering employee in call history."))
                    .accessibilityLabel(NSLocalizedString("Refresh Call Answers", comment: "Refresh answering employee in call history."))
                    .accessibilityIdentifier("history.answers.refresh")
                }
            }
            if let error = model.answerLookupError, canRefreshAnswers {
                Label(answerLookupMessage(for: error), systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onChange(of: model.searchFocusRequest) {
            searchFocused = true
        }
    }

    private func answerLookupMessage(for error: CRMGatewayError) -> String {
        switch error {
        case .callAnswersUnsupported:
            NSLocalizedString("Update CRM Gateway to see call answers.", comment: "Older gateway cannot look up answering employees.")
        case .unauthorized, .missingToken:
            NSLocalizedString("CRM Gateway access is unavailable. Check CRM settings.", comment: "Gateway device authorization failed.")
        default:
            NSLocalizedString("Call answers are unavailable. Refresh to try again.", comment: "Call answer lookup failed.")
        }
    }

}

private struct CallHistoryResults: View {
    @Bindable var model: CallHistoryViewModel
    let call: (String) -> Void
    let copy: (String) -> Void

    var body: some View {
        content
            .task(id: model.answerContext) {
                await model.refreshCallAnswers()
            }
    }

    @ContentBuilder
    private var content: some View {
        if model.records.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $model.selection) {
                ForEach(model.records) { record in
                    CallHistoryRow(record: record, answer: model.callAnswers[record.id])
                        .accessibilityIdentifier("call-history.row.\(record.id)")
                        .tag(record.identifier)
                        .onAppear { model.setAnswerRecordVisible(record.id, visible: true) }
                        .onDisappear { model.setAnswerRecordVisible(record.id, visible: false) }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            model.selectAndCall(record, action: call)
                        }
                        .contextMenu {
                            Button(
                                NSLocalizedString(
                                    "Call Number",
                                    comment:
                                        "Call history context menu item."
                                )
                            ) {
                                model.selectAndCall(record, action: call)
                            }

                            Button(
                                NSLocalizedString(
                                    "Copy Number",
                                    comment:
                                        "Call history context menu item."
                                )
                            ) {
                                copy(record.contact.address)
                            }

                            Divider()

                            Button(
                                NSLocalizedString(
                                    "Delete…",
                                    comment:
                                        "Call history context menu item."
                                ),
                                role: .destructive
                            ) {
                                model.selection = record.identifier
                                _ = model.requestDeleteSelected()
                            }

                            Button(
                                NSLocalizedString(
                                    "Delete All…",
                                    comment:
                                        "Call history context menu item."
                                ),
                                role: .destructive
                            ) {
                                _ = model.requestDeleteAll()
                            }
                        }
                }
            }
            .listStyle(.inset)
            .copyable(copyableAddresses)
            .onKeyPress(.return) {
                model.callSelected(action: call) ? .handled : .ignored
            }
            .onDeleteCommand {
                _ = model.requestDeleteSelected()
            }
        }
    }

    @ContentBuilder
    private var emptyState: some View {
        let query = model.query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if model.filter != .all {
            ContentUnavailableView {
                Label(
                    NSLocalizedString(
                        "No Matching Calls",
                        comment:
                            "Call history filter has no matches title."
                    ),
                    systemImage: "phone"
                )
            } description: {
                Text(
                    NSLocalizedString(
                        "Try a different call filter.",
                        comment:
                            "Call history filter has no matches description."
                    )
                )
            }
        } else {
            ContentUnavailableView {
                Label(
                    NSLocalizedString(
                        "No Calls",
                        comment: "Empty call history title."
                    ),
                    systemImage: "phone"
                )
            } description: {
                Text(
                    NSLocalizedString(
                        "Your call history will appear here.",
                        comment: "Empty call history description."
                    )
                )
            }
        }
    }

    private var copyableAddresses: [String] {
        model.selectedRecord.map { [$0.contact.address] } ?? []
    }

}

private struct CallHistoryFilterMenu: View {
    @Binding var selection: CallHistoryFilter

    var body: some View {
        Menu {
            ForEach(CallHistoryFilter.allCases, id: \.self) { filter in
                Button {
                    selection = filter
                } label: {
                    if selection == filter {
                        Label(filter.title, systemImage: "checkmark")
                    } else {
                        Text(filter.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)

                Text(selection.title)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
        .help(
            NSLocalizedString(
                "Filter Call History",
                comment: "Filter Call History"
            )
        )
        .accessibilityLabel(
            NSLocalizedString(
                "Filter Call History",
                comment:
                    "Call history filter accessibility label."
            )
        )
        .accessibilityValue(selection.title)
    }
}
