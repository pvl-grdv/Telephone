//
//  CustomerContextView.swift
//  Telephone
//

import Foundation
import SwiftUI

struct CustomerContextView: View {
    @Bindable var model: CallWindowModel
    @State private var isExpanded = false

    let changed: () -> Void

    var body: some View {
        Group {
            if !model.customerContextLoaded {
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
            if let profile = model.crmProfile, profile.hasContent {
                crmDetails(profile)
                Divider()
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

    @ViewBuilder
    private func crmDetails(
        _ profile: CRMCustomerProfile
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CRM")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if !profile.company.isEmpty {
                LabeledContent(
                    NSLocalizedString(
                        "Organization",
                        comment: "CRM organization label."
                    ),
                    value: profile.company
                )
                .font(.caption)
            }

            ForEach(
                Array(profile.keys.enumerated()),
                id: \.offset
            ) { _, key in
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.value)
                        .font(.caption.weight(.medium))

                    if !key.programs.isEmpty {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Programs: %@",
                                    comment: "Programs associated with CRM reference key."
                                ),
                                key.programs.joined(separator: ", ")
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if !profile.emails.isEmpty {
                Text(profile.emails.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
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
        let crmCompany = model.crmProfile?.company.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        if !crmCompany.isEmpty,
           !identityAlreadyShows(crmCompany) {
            return crmCompany
        }

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
