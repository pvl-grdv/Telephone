//
//  CustomerContextView.swift
//  Telephone
//

import Foundation
import SwiftUI

struct CustomerContextView: View {
    @Bindable var model: CallWindowModel
    @State private var isExpanded = false
    @State private var confirmsDiscardDraft = false
    var crmKeyLookupModel: CRMKeyLookupModel? = nil

    let changed: () -> Void
    let reload: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            contextContent
            persistenceStatus
            if let crmKeyLookupModel, crmKeyLookupModel.settings.enabled {
                Divider()
                CRMKeyLookupView(model: crmKeyLookupModel)
            }
        }
        .confirmationDialog(
            NSLocalizedString("Reload saved details and discard this draft?", comment: "Explicitly discard conflicting local draft."),
            isPresented: $confirmsDiscardDraft,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Reload saved details", comment: "Reload after local edit conflict."), role: .destructive, action: reload)
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

    @ViewBuilder
    private var contextContent: some View {
        if model.customerContextLoadFailed {
            HStack(spacing: 8) {
                Label(
                    NSLocalizedString(
                        "Couldn’t load client details",
                        comment: "Customer context load failure."
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Button(
                    NSLocalizedString(
                        "Retry",
                        comment: "Retry customer context loading."
                    ),
                    action: reload
                )
                .controlSize(.small)
            }
        } else if !model.customerContextLoaded {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)
                Text(
                    NSLocalizedString(
                        "Loading client details…",
                        comment: "Customer context loading status."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.hasCustomerContextData || isExpanded {
            DisclosureGroup(isExpanded: $isExpanded) {
                editor
                    .padding(.top, 8)
            } label: {
                contextSummary
            }
        } else {
            Button {
                isExpanded = true
            } label: {
                Label(
                    NSLocalizedString(
                        "Add client details",
                        comment: "Expand empty customer context."
                    ),
                    systemImage: "person.crop.circle.badge.plus"
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var persistenceStatus: some View {
        if model.customerContextSaving {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text(
                    NSLocalizedString(
                        "Saving client details…",
                        comment: "Customer context saving status."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } else if model.customerContextSaveConflict {
            VStack(alignment: .leading, spacing: 6) {
                Label(NSLocalizedString("Client details changed in another call", comment: "Optimistic local save conflict."), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                Text(NSLocalizedString("Your draft is kept. Reload saved details to start again.", comment: "Local conflicting draft is preserved."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(NSLocalizedString("Reload saved details", comment: "Reload after local edit conflict.")) { confirmsDiscardDraft = true }
                    .controlSize(.small)
            }
        } else if model.customerContextSaveFailed {
            HStack(spacing: 8) {
                Label(
                    NSLocalizedString(
                        "Couldn’t save client details",
                        comment: "Customer context save failure."
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Button(
                    NSLocalizedString(
                        "Retry",
                        comment: "Retry customer context saving."
                    ),
                    action: save
                )
                .controlSize(.small)
            }
        } else if model.customerContextSaveSucceeded {
            Label(
                NSLocalizedString(
                    "Saved client details",
                    comment: "Customer context saved status."
                ),
                systemImage: "checkmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var contextSummary: some View {
        HStack(spacing: 6) {
            Label(
                summaryTitle,
                systemImage: "person.crop.circle"
            )
            .font(.caption.weight(.semibold))
            .lineLimit(1)

            Spacer(minLength: 4)

            Text(historySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        "Reference keys",
                        comment: "Local customer reference keys field placeholder."
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
                    .accessibilityLabel(
                        NSLocalizedString(
                            "Notes for this call",
                            comment: "Call note editor accessibility label."
                        )
                    )
                    .scrollContentBackground(.hidden)
                    .padding(3)
                    .frame(
                        minHeight: 62,
                        idealHeight: 86,
                        maxHeight: 110
                    )
                    .background(.background, in: .rect(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(.separator, lineWidth: 0.5)
                    }
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
                .accessibilityLabel(label)
        }
    }

    private var summaryTitle: String {
        let company = model.customerCompany.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !company.isEmpty,
           !identityAlreadyShows(company) {
            return company
        }

        return NSLocalizedString(
            "Client details",
            comment: "Collapsed customer context title."
        )
    }

    private func identityAlreadyShows(_ value: String) -> Bool {
        if CallerIdentityPresentation.sameIdentityValue(
            value,
            model.displayedName
        ) {
            return true
        }

        return model.identityDetail
            .components(separatedBy: " · ")
            .contains {
                CallerIdentityPresentation.sameIdentityValue(
                    value,
                    $0
                )
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
