//
//  CustomerContextView.swift
//  Telephone
//

import Foundation
import SwiftUI

struct CustomerContextView: View {
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
                .accessibilityLabel(label)
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
