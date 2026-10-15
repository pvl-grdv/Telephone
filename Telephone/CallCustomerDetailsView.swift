//
//  CallCustomerDetailsView.swift
//  Telephone
//

import SwiftUI

/// Read-only CRM inventory and explicit CRM lookup/write actions for one live
/// call. Call controls, local editors and call timer are independent of this
/// heavy inventory view.
struct CallCustomerDetailsView: View {
    let model: CallWindowModel
    let crmKeyLookupModel: CRMKeyLookupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CallDetailsIdentityHeader(model: model, phone: crmKeyLookupModel.callerPhone)
            CRMKeyLookupView(model: crmKeyLookupModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(minWidth: 660, minHeight: 470)
    }
}

/// Only this lightweight header observes the call status/timer. Changes to
/// the timer must not invalidate the CRM table and its search state.
private struct CallDetailsIdentityHeader: View {
    let model: CallWindowModel
    let phone: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(model.usesDTMFDisplay
                 ? NSLocalizedString("Client details", comment: "Live client details title.")
                 : model.displayedName)
                .font(.headline)
                .lineLimit(1)
            let identity = phone ?? model.identityDetail
            if !identity.isEmpty {
                Text(identity)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Text(model.status)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}
