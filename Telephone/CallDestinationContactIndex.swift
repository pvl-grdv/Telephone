//
//  CallDestinationContactIndex.swift
//  Telephone
//

import Contacts
import Foundation

struct CallDestinationContactAddress: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case phone
        case sip
    }

    let value: String
    let label: String
    let kind: Kind
}

struct CallDestinationContactRecord: Sendable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let organizationName: String
    let givenName: String
    let familyName: String
    let destinations: [CallDestinationContactAddress]
}

actor CallDestinationContactIndex {
    static let shared = CallDestinationContactIndex()

    private var cachedRecords: [CallDestinationContactRecord]?

    func records(
        forceReload: Bool = false
    ) async -> [CallDestinationContactRecord] {
        if !forceReload, let cachedRecords {
            return cachedRecords
        }

        let records = await Task.detached(priority: .userInitiated) {
            let interval = PerformanceSignposts.contacts.beginInterval(
                "LoadContactSuggestionIndex"
            )
            let records = Self.loadRecords()
            PerformanceSignposts.contacts.endInterval(
                "LoadContactSuggestionIndex",
                interval,
                "records=\(records.count)"
            )
            return records
        }.value

        cachedRecords = records
        return records
    }

    func invalidate() {
        cachedRecords = nil
    }

    nonisolated private static func loadRecords()
        -> [CallDestinationContactRecord]
    {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var records: [CallDestinationContactRecord] = []

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let displayName =
                    CNContactFormatter.string(
                        from: contact,
                        style: .fullName
                    ) ?? ""
                let effectiveName = displayName.isEmpty
                    ? contact.organizationName
                    : displayName

                var destinations: [CallDestinationContactAddress] = []
                destinations.reserveCapacity(
                    contact.phoneNumbers.count + contact.emailAddresses.count
                )

                for phone in contact.phoneNumbers {
                    destinations.append(
                        CallDestinationContactAddress(
                            value: phone.value.stringValue,
                            label: localizedLabel(phone.label),
                            kind: .phone
                        )
                    )
                }

                for email in contact.emailAddresses {
                    guard isSIPLabel(email.label) else { continue }

                    destinations.append(
                        CallDestinationContactAddress(
                            value: email.value as String,
                            label: localizedLabel(email.label),
                            kind: .sip
                        )
                    )
                }

                guard !destinations.isEmpty else { return }

                records.append(
                    CallDestinationContactRecord(
                        id: contact.identifier,
                        displayName: effectiveName,
                        organizationName: contact.organizationName,
                        givenName: contact.givenName,
                        familyName: contact.familyName,
                        destinations: destinations
                    )
                )
            }
        } catch {
            NSLog(
                "Could not enumerate contacts for autocomplete: %@",
                error.localizedDescription
            )
        }

        return records
    }

    nonisolated private static func localizedLabel(
        _ label: String?
    ) -> String {
        guard let label, !label.isEmpty else { return "" }
        return CNLabeledValue<NSString>.localizedString(forLabel: label)
    }

    nonisolated private static func isSIPLabel(
        _ label: String?
    ) -> Bool {
        guard let label, !label.isEmpty else { return false }
        let localized = localizedLabel(label)
        return label.caseInsensitiveCompare("sip") == .orderedSame
            || localized.caseInsensitiveCompare("sip") == .orderedSame
    }
}
