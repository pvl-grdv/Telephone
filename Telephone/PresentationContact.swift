//
//  PresentationContact.swift
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

import Foundation
import UseCases

final class PresentationContact: NSObject {
    @objc let title: String
    @objc let tooltip: String
    @objc let label: String
    let address: String

    init(title: String, tooltip: String, label: String, address: String) {
        self.title = title
        self.tooltip = tooltip
        self.label = label
        self.address = address
    }

    var detail: String {
        [label, tooltip]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

extension PresentationContact {
    override func isEqual(_ object: Any?) -> Bool {
        guard let contact = object as? PresentationContact else { return false }
        return isEqual(to: contact)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(tooltip)
        hasher.combine(label)
        hasher.combine(address)
        return hasher.finalize()
    }

    private func isEqual(to contact: PresentationContact) -> Bool {
        title == contact.title
            && tooltip == contact.tooltip
            && label == contact.label
            && address == contact.address
    }
}

extension PresentationContact {
    convenience init(contact: MatchedContact) {
        let address: String
        let label: String

        switch contact.address {
        case let .phone(number, value):
            address = number
            label = value
        case let .email(value, addressLabel):
            address = value
            label = addressLabel
        }

        let identity = CallerIdentityPresentation.make(
            sipDisplayName: "",
            callSource: address,
            contactName: contact.name,
            organization: contact.organization,
            label: ""
        )

        self.init(
            title: identity.primary,
            tooltip: identity.detail,
            label: label,
            address: address
        )
    }
}
