//
//  CallCustomerSummaryView.swift
//  Telephone
//

import SwiftUI

/// Reads only customer state, so the call timer does not rebuild CRM summaries.
struct CallCustomerSummaryView: View {
    let model: CallWindowModel
    let crmKeyLookupModel: CRMKeyLookupModel?
    let showDetails: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: "person.crop.circle")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: showDetails) {
                Label(NSLocalizedString("Client details", comment: "Open live client details."),
                      systemImage: "arrow.up.forward.square")
            }
            .controlSize(.small)
            .fixedSize()
            .accessibilityIdentifier("call.customerDetails")
        }
        .frame(height: 38)
    }

    private var title: String {
        let company: String
        if let crmKeyLookupModel, crmKeyLookupModel.settings.enabled,
           case .loaded(let response) = crmKeyLookupModel.state, let customer = response.data {
            company = customer.company.name
        } else {
            company = model.customerCompany
        }
        return CallCustomerSummaryIdentity.distinctCompany(
            company, displayedName: model.displayedName, identityDetail: model.identityDetail
        ) ?? (crmKeyLookupModel?.settings.enabled == true
              ? NSLocalizedString("CRM", comment: "Compact customer summary without repeated identity.")
              : NSLocalizedString("Client details", comment: "Compact local details summary."))
    }

    private var detail: String {
        if model.customerContextSaveConflict || model.customerContextSaveFailed {
            return NSLocalizedString("Couldn’t save client details", comment: "Local details need attention.")
        }
        if let crmKeyLookupModel, crmKeyLookupModel.settings.enabled {
            switch crmKeyLookupModel.state {
            case .loading:
                return NSLocalizedString("Searching CRM…", comment: "Automatic CRM lookup status.")
            case .loaded(let response):
                if let customer = response.data {
                    return String(format: NSLocalizedString("%ld keys · %ld records", comment: "Compact CRM inventory count."),
                                  customer.keys.count, customer.keys.reduce(0) { $0 + $1.programs.count })
                }
            case .choosing:
                return NSLocalizedString("Several organizations match. Choose one.", comment: "Open details to choose a CRM organization.")
            case .notFound:
                return NSLocalizedString("No organization found. Search by key number or email.", comment: "Open details for manual CRM lookup.")
            case .failed(let error):
                return error.crmMessage
            case .idle:
                break
            }
        }
        if model.customerContextLoadFailed {
            return NSLocalizedString("Couldn’t load client details", comment: "Local details load failed.")
        }
        if !model.customerContextLoaded {
            return NSLocalizedString("Loading client details…", comment: "Local details loading.")
        }
        return model.previousConversationCount > 0
            ? String(format: NSLocalizedString("%ld previous conversations", comment: "Compact client history count."), model.previousConversationCount)
            : NSLocalizedString("No previous conversations", comment: "No local client history.")
    }
}
