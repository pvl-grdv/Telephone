//
//  CNContactStoreToContactsAdapter.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

@preconcurrency import Contacts
import UseCases

final class CNContactStoreToContactsAdapter {
    private let store: CNContactStore

    init(store: CNContactStore) {
        self.store = store
    }
}

extension CNContactStoreToContactsAdapter: Contacts {
    func enumerate(_ body: @escaping (Contact) -> Void) {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else {
            return
        }

        do {
            try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { (contact, _) in
                body(Contact(contact))
            }
        } catch {
            NSLog("Could not enumerate contacts: \(error)")
        }
    }
}

private let keys = [
    CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
    CNContactEmailAddressesKey as CNKeyDescriptor,
    CNContactPhoneNumbersKey as CNKeyDescriptor,
    CNContactOrganizationNameKey as CNKeyDescriptor
]


@objcMembers
final class IncomingCallContact: NSObject, @unchecked Sendable {
    let name: String
    let organization: String
    let label: String

    init(name: String, organization: String, label: String) {
        self.name = name
        self.organization = organization
        self.label = label
    }
}

@objcMembers
final class IncomingCallContactResolver: NSObject {
    private let index: ContactMatchingIndex
    private let settings: ContactMatchingSettings

    init(index: ContactMatchingIndex, settings: ContactMatchingSettings) {
        self.index = index
        self.settings = settings
    }

    func resolve(
        user: String,
        host: String,
        displayName: String,
        domain: String,
        completion: @escaping @MainActor @Sendable (IncomingCallContact?) -> Void
    ) {
        Task { @ContactsActor [index, settings] in
            let matching = IndexedContactMatching(
                index: index,
                significantPhoneNumberLength: await settings.significantPhoneNumberLength,
                domain: domain
            )

            var match = await matching.match(
                for: URI(user: user, host: host, displayName: displayName)
            )

            // Some SIP trunks put the PSTN number into the display-name
            // while the URI user contains an internal routing value.
            if match == nil, !displayName.isEmpty, displayName != user {
                match = await matching.match(
                    for: URI(user: displayName, host: "", displayName: "")
                )
            }

            let result = match.map { contact -> IncomingCallContact in
                let label: String
                switch contact.address {
                case let .phone(_, value), let .email(_, value):
                    label = value
                }
                return IncomingCallContact(
                    name: contact.name,
                    organization: contact.organization,
                    label: label
                )
            }

            await MainActor.run {
                completion(result)
            }
        }
    }
}
