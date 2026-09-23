//
//  TelephoneAppIntents.swift
//  Telephone
//

import AppIntents
import AppKit
import Foundation

struct TelephoneAccountEntity: AppEntity, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Telephone Account"
    )
    static let defaultQuery = TelephoneAccountQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct TelephoneAccountQuery: EntityQuery {
    func entities(
        for identifiers: [TelephoneAccountEntity.ID]
    ) async throws -> [TelephoneAccountEntity] {
        let identifiers = Set(identifiers)
        return Self.accounts().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [TelephoneAccountEntity] {
        Self.accounts()
    }

    private static func accounts() -> [TelephoneAccountEntity] {
        let stored = UserDefaults.standard.array(
            forKey: UserDefaultsKeys.accounts
        ) as? [[String: Any]] ?? []

        return stored.compactMap { account in
            guard
                (account[UserDefaultsKeys.accountEnabled] as? NSNumber)?
                    .boolValue == true,
                let id = account[AKSIPAccountKeys.uuid] as? String,
                !id.isEmpty
            else {
                return nil
            }

            let description =
                account[AKSIPAccountKeys.desc] as? String ?? ""
            let sipAddress =
                account[AKSIPAccountKeys.sipAddress] as? String ?? ""
            let username =
                account[AKSIPAccountKeys.username] as? String ?? ""
            let domain =
                account[AKSIPAccountKeys.domain] as? String ?? ""

            let fallbackAddress: String
            if !sipAddress.isEmpty {
                fallbackAddress = sipAddress
            } else if !username.isEmpty && !domain.isEmpty {
                fallbackAddress = "\(username)@\(domain)"
            } else {
                fallbackAddress = username.isEmpty ? domain : username
            }

            return TelephoneAccountEntity(
                id: id,
                name: description.isEmpty ? fallbackAddress : description
            )
        }
    }
}

enum TelephoneAvailability: String, AppEnum {
    case available
    case unavailable
    case offline

    static let typeDisplayRepresentation =
        TypeDisplayRepresentation(name: "Account Status")

    static let caseDisplayRepresentations:
        [TelephoneAvailability: DisplayRepresentation] = [
            .available: "Available",
            .unavailable: "Unavailable",
            .offline: "Offline",
        ]

    var stateRawValue: Int {
        switch self {
        case .offline:
            AccountAvailabilityState.offline.rawValue
        case .available:
            AccountAvailabilityState.available.rawValue
        case .unavailable:
            AccountAvailabilityState.unavailable.rawValue
        }
    }
}

struct CallWithTelephoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Call with Telephone"
    static let description = IntentDescription(
        "Places a phone or SIP call using Telephone."
    )
    static let supportedModes: IntentModes = .foreground

    @Parameter(
        title: "Destination",
        requestValueDialog: "Who would you like to call?"
    )
    var destination: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let appController = NSApplication.shared.delegate as? AppController
        else {
            return .result(dialog: "Telephone is not ready.")
        }

        let success = appController.makeCallFromAppIntent(
            destination: destination
        )
        if success {
            return .result(dialog: "Calling \(destination).")
        } else {
            return .result(
                dialog: "Telephone couldn't place this call."
            )
        }
    }
}

struct OpenTelephoneSettingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Telephone Settings"
    static let description = IntentDescription(
        "Opens Telephone settings."
    )
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appController = NSApplication.shared.delegate as? AppController
        else {
            return .result()
        }

        appController.showPreferencesForSwiftUI()
        return .result()
    }
}

struct SetTelephoneAccountAvailabilityIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Telephone Account Status"
    static let description = IntentDescription(
        "Changes the availability status of a Telephone SIP account."
    )
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Account")
    var account: TelephoneAccountEntity

    @Parameter(title: "Status")
    var availability: TelephoneAvailability

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let appController = NSApplication.shared.delegate as? AppController
        else {
            return .result(dialog: "Telephone is not ready.")
        }

        let success = appController.setAccountAvailabilityFromAppIntent(
            uuid: account.id,
            state: availability.stateRawValue
        )

        if success {
            return .result(
                dialog: "Updated \(account.name) to \(availability.rawValue)."
            )
        } else {
            return .result(
                dialog: "Telephone couldn't update this account."
            )
        }
    }
}


struct TelephoneAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CallWithTelephoneIntent(),
            phrases: [
                "Call with \(.applicationName)",
            ],
            shortTitle: "Call",
            systemImageName: "phone"
        )

        AppShortcut(
            intent: OpenTelephoneSettingsIntent(),
            phrases: [
                "Open \(.applicationName) settings",
            ],
            shortTitle: "Open Settings",
            systemImageName: "gearshape"
        )

        AppShortcut(
            intent: SetTelephoneAccountAvailabilityIntent(),
            phrases: [
                "Set \(.applicationName) account status",
            ],
            shortTitle: "Set Account Status",
            systemImageName: "person.crop.circle.badge.checkmark"
        )
    }
}
