//
//  CRMGatewayError+Message.swift
//  Telephone
//
//  User-visible gateway errors shared by settings, lookups, and call history.
//

import Foundation

extension CRMGatewayError {
    var crmMessage: String {
        switch self {
        case .disabled:
            NSLocalizedString("CRM lookup is disabled in Settings.", comment: "CRM disabled error.")
        case .invalidOrigin:
            NSLocalizedString("Enter an HTTPS gateway address, or enable HTTP over Tailscale for a 100.64.0.0/10 IPv4 address with an explicit port.", comment: "CRM gateway origin error.")
        case .missingToken:
            NSLocalizedString("Save a gateway token for this address in CRM Settings.", comment: "CRM missing token error.")
        case .invalidKeyNumber:
            NSLocalizedString("Enter a positive numeric key number.", comment: "CRM key number validation.")
        case .invalidPhoneNumber:
            NSLocalizedString("The caller does not have a valid phone number for CRM lookup.", comment: "CRM phone validation failure.")
        case .invalidEmail:
            NSLocalizedString("Enter one valid email address.", comment: "CRM invalid email address.")
        case .invalidOrganizationCode:
            NSLocalizedString("Enter an organization number like 12-34-5678.", comment: "CRM registration number validation.")
        case .organizationCodeUnsupported:
            NSLocalizedString("Update CRM Gateway to search by registration number.", comment: "Gateway registration number lookup is unavailable.")
        case .forbidden:
            NSLocalizedString("This gateway token cannot link phone numbers. Ask the gateway operator to enable this permission.", comment: "CRM phone append permission failure.")
        case .conflict:
            NSLocalizedString("The organization’s phones changed. Refresh its details before linking the number.", comment: "CRM optimistic concurrency conflict.")
        case .phoneWriteUnconfirmed:
            NSLocalizedString("Couldn’t confirm the phone association. Refresh the organization before trying again.", comment: "CRM unknown phone write outcome.")
        case .unauthorized:
            NSLocalizedString("The gateway rejected the token. Update it in CRM Settings.", comment: "CRM authorization error.")
        case .unavailable:
            NSLocalizedString("The gateway or CRM is unavailable. Check the connection and try again.", comment: "CRM unavailable error.")
        case .rateLimited:
            NSLocalizedString("Too many requests. Try again shortly.", comment: "CRM rate limit error.")
        case .redirectDenied:
            NSLocalizedString("The gateway redirected the request. Check its address in CRM Settings.", comment: "CRM redirect refusal.")
        case .invalidResponse:
            NSLocalizedString("The gateway returned an incomplete or invalid response.", comment: "CRM contract failure.")
        case .statusUnsupported:
            NSLocalizedString("Gateway version unknown: this gateway does not support status checks.", comment: "Older gateway status route returns 404.")
        case .callAnswersUnsupported:
            NSLocalizedString("Update CRM Gateway to see call answers.", comment: "Older gateway cannot look up answering employees.")
        case .keychain:
            NSLocalizedString("Couldn’t save or remove the gateway token in Keychain.", comment: "CRM Keychain failure.")
        }
    }
}
