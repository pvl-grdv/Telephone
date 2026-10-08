//
//  CallCustomerDetailsView.swift
//  Telephone
//

import SwiftUI

/// A separate nonmodal editor for the same live call models. It deliberately
/// publishes no call commands and contains no answer, hang-up, or DTMF surface.
struct CallCustomerDetailsView: View {
    let model: CallWindowModel
    let crmKeyLookupModel: CRMKeyLookupModel?
    let changed: () -> Void
    let reload: () -> Void
    let save: () -> Void
    let close: () -> Void
    @State private var selectedSection = Section.crm

    private enum Section: Hashable {
        case crm, localNotes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.usesDTMFDisplay
                     ? NSLocalizedString("Client details", comment: "Live client details title.") : model.displayedName)
                    .font(.headline)
                    .lineLimit(1)
                let identity = crmKeyLookupModel?.callerPhone ?? model.identityDetail
                if !identity.isEmpty {
                    Text(identity).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Text(model.status).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            if let crmKeyLookupModel, crmKeyLookupModel.settings.enabled {
                Picker(NSLocalizedString("Client details", comment: "Live client details section selector."),
                       selection: $selectedSection) {
                    Text(NSLocalizedString("CRM", comment: "Live CRM tab.")).tag(Section.crm)
                    Text(NSLocalizedString("Local notes", comment: "Telephone-only client notes tab.")).tag(Section.localNotes)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("call.customerDetails.section")

                // Keep both panes mounted so switching preserves inventory search,
                // key selection, and the local editor. Only the selected pane can
                // receive input, keyboard shortcuts, or accessibility focus.
                ZStack(alignment: .topLeading) {
                    CRMKeyLookupView(model: crmKeyLookupModel)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .opacity(selectedSection == .crm ? 1 : 0)
                        .disabled(selectedSection != .crm)
                        .allowsHitTesting(selectedSection == .crm)
                        .accessibilityHidden(selectedSection != .crm)
                    localDetails
                        .opacity(selectedSection == .localNotes ? 1 : 0)
                        .disabled(selectedSection != .localNotes)
                        .allowsHitTesting(selectedSection == .localNotes)
                        .accessibilityHidden(selectedSection != .localNotes)
                }
            } else {
                localDetails
            }
            HStack {
                Spacer()
                Button(NSLocalizedString("Close", comment: "Close live client details without ending the call."), action: close)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("call.closeCustomerDetails")
            }
        }
        .padding(16)
        .frame(minWidth: 660, minHeight: 500)
    }

    private var localDetails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("These details are saved in Telephone and do not change CRM.",
                                       comment: "Local fields are independent of gateway CRM data."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                CustomerContextView(model: model, changed: changed, reload: reload, save: save)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
