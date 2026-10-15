//
//  CallHistoryScreen.swift
//  Telephone
//

import SwiftUI

struct CallHistoryScreen: View {
    @Bindable var model: CallHistoryViewModel
    @FocusState private var searchFocused: Bool

    let call: (String) -> Void
    let copy: (String) -> Void
    let deleteRecord: (String) -> Void
    let deleteAll: () -> Void

    init(
        model: CallHistoryViewModel,
        call: @escaping (String) -> Void,
        copy: @escaping (String) -> Void,
        deleteRecord: @escaping (String) -> Void,
        deleteAll: @escaping () -> Void
    ) {
        self.model = model
        self.call = call
        self.copy = copy
        self.deleteRecord = deleteRecord
        self.deleteAll = deleteAll
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
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
        .onChange(of: model.searchFocusRequest) {
            searchFocused = true
        }
        .task(id: model.answerContext) {
            await model.refreshCallAnswers()
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

    private var controls: some View {
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

                if !model.answerContext.calls.isEmpty {
                    Button {
                        model.answerRefreshRequest &+= 1
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(NSLocalizedString("Refresh Call Answers", comment: "Refresh answering employee in call history."))
                    .accessibilityLabel(NSLocalizedString("Refresh Call Answers", comment: "Refresh answering employee in call history."))
                }
            }
            if let error = model.answerLookupError, !model.answerContext.calls.isEmpty {
                Label(answerLookupMessage(for: error), systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        .frame(width: 112, alignment: .leading)
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

private struct CallHistoryRow: View {
    let record: PresentationCallHistoryRecord
    let answer: CRMIncomingCallAnswer?

    private var notAnsweredLocally: Bool {
        record.isIncoming && (record.isMissed || record.durationSeconds == 0)
    }
    private var answeredElsewhere: Bool {
        notAnsweredLocally && answer?.status == .answered
    }
    private var globallyUnanswered: Bool {
        notAnsweredLocally && answer?.status == .unanswered
    }
    private var showsMissed: Bool {
        (record.isMissed && !answeredElsewhere) || globallyUnanswered
    }

    private var answerDetail: String? {
        guard let answer else { return nil }
        if answer.status == .answered, let employee = answer.answeredBy {
            return String(
                format: NSLocalizedString("Answered by: %@", comment: "Answering employee from the call service."),
                employee.displayName
            )
        }
        guard answer.status == .unknown else { return nil }
        switch answer.reason {
        case "not-found":
            return NSLocalizedString("ATS: no matching call", comment: "Call answer lookup found no matching PBX record.")
        case "time-mismatch":
            return NSLocalizedString("ATS: call time does not match", comment: "Caller exists in PBX but no record matches the SIP start time.")
        case "ambiguous":
            return NSLocalizedString("ATS: multiple possible calls", comment: "More than one PBX call could match.")
        case "transferred":
            return NSLocalizedString("ATS: transferred call", comment: "Transfer prevents reliable answering employee attribution.")
        case "not-confirmed":
            return NSLocalizedString("ATS: answer not confirmed", comment: "PBX did not confirm a completed answered call.")
        case "identity-unavailable":
            return NSLocalizedString("ATS: employee not identified", comment: "PBX outcome does not identify who answered.")
        default:
            return nil
        }
    }

    private var directionSymbol: String {
        record.isIncoming
            ? "phone.arrow.down.left.fill"
            : "phone.arrow.up.right.fill"
    }

    private var statusText: String {
        if answeredElsewhere {
            return NSLocalizedString("Answered Elsewhere", comment: "Incoming call answered by another employee.")
        }
        if globallyUnanswered {
            return NSLocalizedString("No One Answered", comment: "ATS confirmed an unanswered incoming call.")
        }
        return record.isMissed
            ? NSLocalizedString(
                "Not Answered Here",
                comment: "Incoming call was not answered on this account; overall outcome may be unknown."
            )
            : record.duration
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: directionSymbol)
                .font(.caption)
                .foregroundStyle(
                    showsMissed ? Color.red : Color.secondary
                )
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.contact.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(
                        showsMissed ? Color.red : Color.primary
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(record.contact.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: 14, alignment: .leading)
                if let detail = answerDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(answer?.status == .answered
                            ? NSLocalizedString("Matched by caller number and call time.", comment: "Call answer correlation provenance.")
                            : detail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(record.date)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(
                        showsMissed ? Color.red : Color.secondary
                    )
                    .lineLimit(1)
                    .frame(height: 14, alignment: .trailing)
            }
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .help(record.contact.address)
        .accessibilityElement(children: .combine)
    }
}
