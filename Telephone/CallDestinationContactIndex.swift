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

    private struct PendingLoad: Sendable {
        let generation: UUID
        let task: Task<[CallDestinationContactRecord], Never>
    }

    private let loader: @Sendable () async -> [CallDestinationContactRecord]
    private var generation = UUID()
    private var pendingLoad: PendingLoad?
    private var cachedRecords: [CallDestinationContactRecord]?

    init(
        loader: @escaping @Sendable () async -> [CallDestinationContactRecord] = {
            CallDestinationContactIndex.loadRecords()
        }
    ) {
        self.loader = loader
    }

    deinit {
        pendingLoad?.task.cancel()
    }

    func records(
        forceReload: Bool = false
    ) async -> [CallDestinationContactRecord] {
        guard !Task.isCancelled else { return [] }
        if forceReload {
            invalidate()
        }

        while !Task.isCancelled {
            if let cachedRecords {
                return cachedRecords
            }

            let load: PendingLoad
            if let pendingLoad {
                load = pendingLoad
            } else {
                let loader = self.loader
                let task = Task<[CallDestinationContactRecord], Never>.detached(
                    priority: .userInitiated
                ) {
                    guard !Task.isCancelled else { return [] }
                    let interval = PerformanceSignposts.contacts.beginInterval(
                        "LoadContactSuggestionIndex"
                    )
                    let records = await loader()
                    PerformanceSignposts.contacts.endInterval(
                        "LoadContactSuggestionIndex",
                        interval,
                        "records=\(records.count)"
                    )
                    return records
                }
                load = PendingLoad(generation: generation, task: task)
                pendingLoad = load
            }

            let records = await load.task.value
            guard !Task.isCancelled else { return [] }

            // An invalidation or a newer forced refresh may have occurred while
            // awaiting Contacts. Retry the current generation for this caller;
            // the superseded result must neither escape nor refill the cache.
            guard load.generation == generation else { continue }

            cachedRecords = records
            pendingLoad = nil
            return records
        }
        return []
    }

    func invalidate() {
        generation = UUID()
        pendingLoad?.task.cancel()
        pendingLoad = nil
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
            try store.enumerateContacts(with: request) { contact, stop in
                guard !Task.isCancelled else {
                    stop.pointee = true
                    return
                }
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
            let nsError = error as NSError
            Log.contacts.error(
                """
                Could not enumerate contacts for autocomplete \
                domain=\(nsError.domain, privacy: .public) \
                code=\(nsError.code, privacy: .public) \
                description=\(nsError.localizedDescription, privacy: .private)
                """
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
