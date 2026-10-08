//
//  CompactCallView.swift
//  Telephone
//

import SwiftUI

/// The live call surface has no editor or inventory. Its size does not depend
/// on the number of organizations, keys, programs, or notes returned by CRM.
struct CompactCallView: View {
    let model: CallWindowModel
    let crmKeyLookupModel: CRMKeyLookupModel?
    let showsCustomerContext: Bool
    let answer: () -> Void
    let decline: () -> Void
    let hangUp: () -> Void
    let toggleMute: () -> Void
    let toggleHold: () -> Void
    let showTransfer: () -> Void
    let redial: () -> Void
    let showCustomerDetails: () -> Void
    let sendDTMF: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            DTMFInputSurface(focusRequest: model.callSurfaceFocusRequest, sendDTMF: sendDTMF) {
                callStateContent
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showsCustomerContext {
                Divider()
                CallCustomerSummaryView(model: model, crmKeyLookupModel: crmKeyLookupModel,
                                        showDetails: showCustomerDetails)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }

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
            IncomingCallSection(model: model, answer: answer, decline: decline)
        case .active:
            ActiveCallSection(model: model, hangUp: hangUp, toggleMute: toggleMute,
                              toggleHold: toggleHold, showTransfer: showTransfer)
        case .ended:
            EndedCallSection(model: model, redial: redial)
        case .transferDestination, .transferActive, .transferEnded:
            EmptyView()
        }
    }
}
