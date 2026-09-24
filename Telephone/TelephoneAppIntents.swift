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

@available(macOS 27.0, *)
@AppEntity(schema: .phone.phonePerson)
struct TelephonePhonePerson {
    static let defaultQuery = TelephonePhonePersonQuery()

    let id: String
    var person: IntentPerson

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }

    init(person: IntentPerson) {
        let identifier = Self.identifier(for: person)
        id = identifier
        self.person = person
    }

    init?(identifier: String) {
        let components = identifier.split(
            separator: ":",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard components.count == 2 else {
            return nil
        }

        let value = String(components[1])
        let handle: IntentPerson.Handle
        switch components[0] {
        case "phone":
            handle = IntentPerson.Handle(phoneNumber: value)
        case "email":
            handle = IntentPerson.Handle(emailAddress: value)
        case "app":
            handle = IntentPerson.Handle(applicationDefined: value)
        default:
            return nil
        }

        id = identifier
        person = IntentPerson(handle: handle)
    }

    var callTarget: String? {
        guard let handle = person.handle else {
            return nil
        }

        switch handle.value {
        case .phoneNumber(let value):
            return value
        case .emailAddress(let value):
            return value
        case .applicationDefined(let value):
            return value
        @unknown default:
            return nil
        }
    }

    private var displayName: String {
        let value = Self.displayName(for: person).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return value.isEmpty ? (callTarget ?? id) : value
    }

    private static func identifier(for person: IntentPerson) -> String {
        guard let handle = person.handle else {
            return "app:\(displayName(for: person))"
        }

        switch handle.value {
        case .phoneNumber(let value):
            return "phone:\(value)"
        case .emailAddress(let value):
            return "email:\(value)"
        case .applicationDefined(let value):
            return "app:\(value)"
        @unknown default:
            return "app:\(displayName(for: person))"
        }
    }

    private static func displayName(for person: IntentPerson) -> String {
        switch person.name {
        case .displayName(let value):
            return value
        case .components(let components):
            return PersonNameComponentsFormatter.localizedString(
                from: components,
                style: .default,
                options: []
            )
        case .unknown:
            return ""
        @unknown default:
            return ""
        }
    }
}

@available(macOS 27.0, *)
struct TelephonePhonePersonQuery: EntityQuery {
    func entities(
        for identifiers: [TelephonePhonePerson.ID]
    ) async throws -> [TelephonePhonePerson] {
        identifiers.compactMap(TelephonePhonePerson.init(identifier:))
    }
}

@available(macOS 27.0, *)
extension TelephonePhonePersonQuery: IntentValueQuery {
    func values(
        for input: [IntentPerson]
    ) async throws -> [TelephonePhonePerson] {
        input.map(TelephonePhonePerson.init(person:))
    }
}

@available(macOS 27.0, *)
@UnionValue
enum TelephoneCallDestination {
    case person(TelephonePhonePerson)
    case people([TelephonePhonePerson])

    var people: [TelephonePhonePerson] {
        switch self {
        case .person(let person):
            [person]
        case .people(let people):
            people
        }
    }
}

@available(macOS 27.0, *)
@AppEnum(schema: .phone.audioVisualMode)
enum TelephoneCallAVMode: String {
    case audio
    case video

    static let caseDisplayRepresentations:
        [TelephoneCallAVMode: DisplayRepresentation] = [
            .audio: "Audio",
            .video: "Video",
        ]
}

@available(macOS 27.0, *)
@AppIntent(schema: .phone.startCall)
struct StartTelephoneCallIntent: AudioRecordingIntent, AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Call with Telephone"
    static let supportedModes: IntentModes = .foreground

    var destination: TelephoneCallDestination
    var audioVisualMode: TelephoneCallAVMode

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard audioVisualMode == .audio else {
            return .result(
                dialog: "Telephone supports audio calls only."
            )
        }

        let targets = destination.people.compactMap(\.callTarget)
        guard targets.count == 1, let target = targets.first else {
            return .result(
                dialog: "Telephone supports one destination per call."
            )
        }

        guard let appController = NSApplication.shared.delegate as? AppController
        else {
            return .result(dialog: "Telephone is not ready.")
        }

        let success = appController.makeCallFromAppIntent(
            destination: target
        )
        return success
            ? .result(dialog: "Calling \(target).")
            : .result(dialog: "Telephone couldn't place this call.")
    }

}

struct CallWithTelephoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Dial with Telephone"
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
                "Dial with \(.applicationName)",
            ],
            shortTitle: "Dial",
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
