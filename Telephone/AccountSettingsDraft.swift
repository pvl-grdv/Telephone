//
//  AccountSettingsDraft.swift
//  Telephone
//
//  Conversion between editable SIP account values and stored settings.
//

import Foundation
import UseCases

struct AccountSettingsSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let isEnabled: Bool
}

enum AccountIPUpdateMode: Int, CaseIterable, Hashable {
    case off
    case partial
    case all

    var title: String {
        switch self {
        case .off:
            NSLocalizedString("Off", comment: "Account IP address update mode.")
        case .partial:
            NSLocalizedString("Partial", comment: "Account IP address update mode.")
        case .all:
            NSLocalizedString("All", comment: "Account IP address update mode.")
        }
    }
}

struct AccountSettingsDraft: Equatable {
    var isEnabled = false
    var descriptionText = ""
    var fullName = ""
    var domain = ""
    var username = ""
    var password = ""
    var sipAddress = ""
    var registrar = ""
    var reregistrationTime = ""
    var substitutesPlusCharacter = false
    var plusCharacterSubstitution = "00"
    var usesProxy = false
    var proxyHost = ""
    var proxyPort = ""
    var transport = AKSIPAccountKeys.transportUDP
    var ipVersion = AKSIPAccountKeys.ipVersion4
    var ipUpdateMode: AccountIPUpdateMode = .all
}

extension AccountSettingsDraft {
    init(storedAccount account: [String: Any]) {
        let registrar = Self.stringValue(account[AKSIPAccountKeys.registrar])
        let domain = Self.stringValue(account[AKSIPAccountKeys.domain])
        let username = Self.stringValue(account[AKSIPAccountKeys.username])

        let updateContact = Self.boolValue(account[AKSIPAccountKeys.updateContactHeader])
        let updateVia = Self.boolValue(account[AKSIPAccountKeys.updateViaHeader])
        let updateSDP = Self.boolValue(account[AKSIPAccountKeys.updateSDP])
        let updateMode: AccountIPUpdateMode
        if updateContact && updateVia && updateSDP {
            updateMode = .all
        } else if updateContact || updateVia || updateSDP {
            updateMode = .partial
        } else {
            updateMode = .off
        }

        self.init(
                isEnabled: Self.boolValue(account[UserDefaultsKeys.accountEnabled]),
                descriptionText: Self.stringValue(account[AKSIPAccountKeys.desc]),
                fullName: Self.stringValue(account[AKSIPAccountKeys.fullName]),
                domain: domain,
                username: username,
                password: "",
                sipAddress: Self.stringValue(account[AKSIPAccountKeys.sipAddress]),
                registrar: registrar,
                reregistrationTime: Self.positiveIntegerString(
                    account[AKSIPAccountKeys.reregistrationTime]
                ),
                substitutesPlusCharacter: Self.boolValue(
                    account[UserDefaultsKeys.substitutePlusCharacter]
                ),
                plusCharacterSubstitution: Self.stringValue(
                    account[UserDefaultsKeys.plusCharacterSubstitutionString],
                    defaultValue: "00"
                ),
                usesProxy: Self.boolValue(account[AKSIPAccountKeys.useProxy]),
                proxyHost: Self.stringValue(account[AKSIPAccountKeys.proxyHost]),
                proxyPort: Self.positiveIntegerString(account[AKSIPAccountKeys.proxyPort]),
                transport: Self.stringValue(
                    account[AKSIPAccountKeys.transport],
                    defaultValue: AKSIPAccountKeys.transportUDP
                ),
                ipVersion: Self.stringValue(
                    account[AKSIPAccountKeys.ipVersion],
                    defaultValue: AKSIPAccountKeys.ipVersion4
                ),
                ipUpdateMode: updateMode
        )
    }

    func write(to account: inout [String: Any]) {
        account[AKSIPAccountKeys.desc] = Self.trimmed(descriptionText)
        account[AKSIPAccountKeys.fullName] = Self.trimmed(fullName)
        account[AKSIPAccountKeys.domain] = Self.trimmed(domain)
        account[AKSIPAccountKeys.username] = Self.trimmed(username)
        account[AKSIPAccountKeys.reregistrationTime] =
            Self.integerValue(reregistrationTime)
        account[UserDefaultsKeys.substitutePlusCharacter] =
            substitutesPlusCharacter
        account[UserDefaultsKeys.plusCharacterSubstitutionString] =
            plusCharacterSubstitution
        account[AKSIPAccountKeys.useProxy] = usesProxy
        account[AKSIPAccountKeys.proxyHost] = Self.trimmed(proxyHost)
        if let proxyPort = SIPPortValidation.value(proxyPort) {
            account[AKSIPAccountKeys.proxyPort] = proxyPort
        }
        account[AKSIPAccountKeys.sipAddress] = Self.trimmed(sipAddress)
        account[AKSIPAccountKeys.registrar] = Self.trimmed(registrar)
        account[AKSIPAccountKeys.transport] = transport
        account[AKSIPAccountKeys.ipVersion] = ipVersion

        switch ipUpdateMode {
        case .all:
            account[AKSIPAccountKeys.updateContactHeader] = true
            account[AKSIPAccountKeys.updateViaHeader] = true
            account[AKSIPAccountKeys.updateSDP] = true
        case .partial:
            account[AKSIPAccountKeys.updateContactHeader] = true
            account[AKSIPAccountKeys.updateViaHeader] = true
            account[AKSIPAccountKeys.updateSDP] = false
        case .off:
            account[AKSIPAccountKeys.updateContactHeader] = false
            account[AKSIPAccountKeys.updateViaHeader] = false
            account[AKSIPAccountKeys.updateSDP] = false
        }
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func integerValue(_ value: String) -> Int {
        Int(trimmed(value)) ?? 0
    }

    private static func positiveIntegerString(_ value: Any?) -> String {
        let integer = (value as? NSNumber)?.intValue ?? 0
        return integer > 0 ? String(integer) : ""
    }

    private static func boolValue(_ value: Any?) -> Bool {
        (value as? NSNumber)?.boolValue ?? false
    }

    private static func stringValue(
        _ value: Any?,
        defaultValue: String = ""
    ) -> String {
        value as? String ?? defaultValue
    }
}
