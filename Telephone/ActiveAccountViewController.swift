//
//  ActiveAccountViewController.swift
//  Telephone
//

import AppKit
@preconcurrency import Contacts
import SwiftUI

extension Notification.Name {
    static let AKContactsAuthorizationDidChange =
        Notification.Name("TelephoneContactsAuthorizationDidChange")
}

private final class CallDestination: NSObject {
    let uri: AKSIPURI
    let phoneLabel: String

    init(uri: AKSIPURI, phoneLabel: String) {
        self.uri = uri
        self.phoneLabel = phoneLabel
    }
}

private final class CallDestinationGroup: NSObject {
    let destinations: [CallDestination]
    var selectedIndex: Int

    var selectedDestination: CallDestination? {
        guard destinations.indices.contains(selectedIndex) else { return nil }
        return destinations[selectedIndex]
    }

    init(destinations: [CallDestination], selectedIndex: Int) {
        self.destinations = destinations
        self.selectedIndex = destinations.indices.contains(selectedIndex) ? selectedIndex : 0
    }
}

private struct ContactCachePayload: @unchecked Sendable {
    let contacts: [CNContact]
}

@MainActor
@objcMembers
class ActiveAccountViewController: NSViewController, NSTokenFieldDelegate {
    private weak var storedAccountController: AccountController?
    private let field = NSTokenField(frame: .zero)

    private var contactStore = CNContactStore()
    private var contactsCache: [CNContact]?
    private var contactsCacheLoading = false
    private var contactsPermissionRequestInFlight = false

    var accountController: AccountController? {
        storedAccountController
    }

    var callDestinationField: NSTokenField {
        field
    }

    var callDestinationURI: AKSIPURI? {
        guard
            let uri = callDestinationGroup?.selectedDestination?.uri.copy() as? AKSIPURI,
            !uri.user.isEmpty
        else {
            return nil
        }
        return uri
    }

    var callDestinationPhoneLabel: String {
        callDestinationGroup?.selectedDestination?.phoneLabel ?? ""
    }

    var allowsCallDestinationInput: Bool {
        !field.isHidden
    }

    var keyView: NSView {
        field
    }

    private var callDestinationGroup: CallDestinationGroup? {
        guard
            let tokens = field.objectValue as? [Any],
            let group = tokens.first as? CallDestinationGroup
        else {
            return nil
        }
        return group
    }

    @objc(initWithAccountController:)
    init(accountController: AccountController) {
        storedAccountController = accountController
        super.init(nibName: nil, bundle: nil)

        field.focusRingType = .none
        field.tokenizingCharacterSet = CharacterSet()
        field.completionDelay = 0.4
        field.delegate = self
        field.target = self
        field.action = #selector(makeCall(_:))
        field.tokenStyle = .none
        field.isHidden = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contactsDidChange(_:)),
            name: .CNContactStoreDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(callDestinationTextDidBeginEditing(_:)),
            name: NSControl.textDidBeginEditingNotification,
            object: field
        )

        if CNContactStore.authorizationStatus(for: .contacts) == .authorized {
            refreshContactsCache()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        view = NSHostingView(rootView: ActiveAccountInputView(field: field))
    }

    @IBAction func makeCall(_ sender: Any?) {
        guard let uri = callDestinationURI else { return }
        storedAccountController?.makeCall(
            to: uri,
            phoneLabel: callDestinationPhoneLabel
        )
    }

    func makeCallToDestination(_ destination: String) {
        field.tokenStyle = .rounded
        field.stringValue = destination
        normalizeCurrentDestination()
        makeCall(self)
    }

    func allowCallDestinationInput() {
        field.isHidden = false
        if field.acceptsFirstResponder {
            view.window?.makeFirstResponder(field)
        }
    }

    func disallowCallDestinationInput() {
        field.isHidden = true
    }

    func updateNextKeyView(_ view: NSView) {
        keyView.nextKeyView = view
    }

    @objc private func callDestinationTextDidBeginEditing(_ notification: Notification) {
        requestContactsAccessIfNeeded()
    }

    @objc private func contactsDidChange(_ notification: Notification) {
        if CNContactStore.authorizationStatus(for: .contacts) == .authorized {
            refreshContactsCache()
        } else {
            contactsCache = []
        }
    }

    private func requestContactsAccessIfNeeded() {
        let status = CNContactStore.authorizationStatus(for: .contacts)

        if status == .authorized {
            if contactsCache == nil {
                refreshContactsCache()
            }
            return
        }

        guard status == .notDetermined, !contactsPermissionRequestInFlight else { return }

        contactsPermissionRequestInFlight = true
        contactStore.requestAccess(for: .contacts) { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }

                self.contactsPermissionRequestInFlight = false
                guard granted else {
                    if let error {
                        NSLog("Could not get Contacts access: %@", error.localizedDescription)
                    }
                    return
                }

                self.refreshContactsCache()
                NotificationCenter.default.post(
                    name: .AKContactsAuthorizationDidChange,
                    object: nil
                )
            }
        }
    }

    private func refreshContactsCache() {
        guard !contactsCacheLoading else { return }

        contactsCacheLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let payload = ContactCachePayload(
                contacts: Self.allContacts(in: CNContactStore())
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.contactsCache = payload.contacts
                self.contactsCacheLoading = false
            }
        }
    }

    nonisolated private static func allContacts(in store: CNContactStore) -> [CNContact] {
        var contacts: [CNContact] = []
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                contacts.append(contact)
            }
        } catch {
            NSLog("Could not enumerate contacts for autocomplete: %@", error.localizedDescription)
        }
        return contacts
    }

    private func normalizeCurrentDestination() {
        guard let represented = representedDestination(for: field.stringValue) else { return }
        field.objectValue = [represented]
    }

    private func representedDestination(for editingString: String) -> CallDestinationGroup? {
        let trimmed = editingString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uri = parseURI(trimmed), !uri.user.isEmpty else { return nil }

        let contact = matchingContact(
            for: uri,
            displayedName: uri.displayName,
            contacts: contactsCache ?? []
        )

        var destinations: [CallDestination] = []
        var selectedIndex = 0

        if let contact {
            let displayName = contactDisplayName(contact)
            if !displayName.isEmpty {
                uri.displayName = displayName
            }

            let targetPhone = normalizedPhoneNumber(uri.user)

            for phone in contact.phoneNumbers {
                let phoneNumber = phone.value.stringValue
                guard let candidate = parseURI(phoneNumber) else { continue }
                candidate.displayName = uri.displayName
                destinations.append(
                    CallDestination(
                        uri: candidate,
                        phoneLabel: localizedContactLabel(phone.label)
                    )
                )

                if uri.host.isEmpty,
                   !targetPhone.isEmpty,
                   normalizedPhoneNumber(phoneNumber) == targetPhone {
                    selectedIndex = destinations.count - 1
                }
            }

            for email in contact.emailAddresses {
                guard isSIPLabel(email.label) else { continue }

                let address = email.value as String
                guard let candidate = parseURI(address) else { continue }
                candidate.displayName = uri.displayName
                destinations.append(
                    CallDestination(
                        uri: candidate,
                        phoneLabel: localizedContactLabel(email.label)
                    )
                )

                if address.caseInsensitiveCompare(uri.sipAddress) == .orderedSame {
                    selectedIndex = destinations.count - 1
                }
            }
        }

        if destinations.isEmpty {
            destinations.append(CallDestination(uri: uri, phoneLabel: ""))
        }

        return CallDestinationGroup(destinations: destinations, selectedIndex: selectedIndex)
    }

    private func parseURI(_ string: String) -> AKSIPURI? {
        let formatter = configuredSIPFormatter()
        var object: AnyObject?
        var error: NSString?
        guard formatter.getObjectValue(&object, for: string, errorDescription: &error) else {
            if let error {
                NSLog("%@", error)
            }
            return nil
        }
        return object as? AKSIPURI
    }

    private func configuredSIPFormatter() -> AKSIPURIFormatter {
        let defaults = UserDefaults.standard
        let formatter = AKSIPURIFormatter()
        formatter.formatsTelephoneNumbers = defaults.bool(forKey: UserDefaultsKeys.formatTelephoneNumbers)
        formatter.telephoneNumberFormatterSplitsLastFourDigits =
            defaults.bool(forKey: UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits)
        return formatter
    }

    private func formattedPhoneNumber(_ value: String) -> String {
        let formatter = AKTelephoneNumberFormatter()
        formatter.splitsLastFourDigits =
            UserDefaults.standard.bool(forKey: UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits)
        return formatter.string(for: value) ?? value
    }

    private func normalizedPhoneNumber(_ value: String) -> String {
        let allowed = value.filter { $0.isNumber || $0 == "+" }
        return allowed
    }

    private func contactDisplayName(_ contact: CNContact) -> String {
        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        return name.isEmpty ? contact.organizationName : name
    }

    private func localizedContactLabel(_ label: String?) -> String {
        guard let label, !label.isEmpty else { return "" }
        return CNLabeledValue<NSString>.localizedString(forLabel: label)
    }

    private func isSIPLabel(_ label: String?) -> Bool {
        guard let label, !label.isEmpty else { return false }
        let localized = localizedContactLabel(label)
        return label.caseInsensitiveCompare("sip") == .orderedSame
            || localized.caseInsensitiveCompare("sip") == .orderedSame
    }

    private func hasCaseInsensitivePrefix(_ value: String, _ prefix: String) -> Bool {
        guard !value.isEmpty, !prefix.isEmpty else { return false }
        return value.range(
            of: prefix,
            options: [.caseInsensitive, .anchored]
        ) != nil
    }

    private func contactMatchesName(_ contact: CNContact, query: String) -> Bool {
        let givenFamily = "\(contact.givenName) \(contact.familyName)"
        let familyGiven = "\(contact.familyName) \(contact.givenName)"

        return hasCaseInsensitivePrefix(contactDisplayName(contact), query)
            || hasCaseInsensitivePrefix(contact.givenName, query)
            || hasCaseInsensitivePrefix(contact.familyName, query)
            || hasCaseInsensitivePrefix(givenFamily, query)
            || hasCaseInsensitivePrefix(familyGiven, query)
            || hasCaseInsensitivePrefix(contact.organizationName, query)
    }

    private func phoneMatchesPrefix(_ phoneNumber: String, query: String) -> Bool {
        let normalizedPhone = normalizedPhoneNumber(phoneNumber)
        let normalizedQuery = normalizedPhoneNumber(query)
        return !normalizedQuery.isEmpty && normalizedPhone.hasPrefix(normalizedQuery)
    }

    private func contactNameEquals(_ contact: CNContact, name: String) -> Bool {
        guard !name.isEmpty else { return true }
        return contactDisplayName(contact).caseInsensitiveCompare(name) == .orderedSame
            || contact.organizationName.caseInsensitiveCompare(name) == .orderedSame
    }

    private func matchingContact(
        for uri: AKSIPURI,
        displayedName: String,
        contacts: [CNContact]
    ) -> CNContact? {
        var fallback: CNContact?

        for contact in contacts {
            let addressMatches: Bool

            if uri.host.isEmpty {
                let target = normalizedPhoneNumber(uri.user)
                addressMatches = contact.phoneNumbers.contains {
                    !target.isEmpty
                        && normalizedPhoneNumber($0.value.stringValue) == target
                }
            } else {
                let target = uri.sipAddress
                addressMatches = contact.emailAddresses.contains {
                    isSIPLabel($0.label)
                        && ($0.value as String).caseInsensitiveCompare(target) == .orderedSame
                }
            }

            guard addressMatches else { continue }

            if contactNameEquals(contact, name: displayedName) {
                return contact
            }
            if fallback == nil {
                fallback = contact
            }
        }

        return fallback
    }

    @objc private func changeCallDestinationURIIndex(_ sender: NSMenuItem) {
        guard
            let group = callDestinationGroup,
            group.destinations.indices.contains(sender.tag)
        else {
            return
        }

        group.selectedIndex = sender.tag
        field.needsDisplay = true
    }

    func tokenField(
        _ tokenField: NSTokenField,
        completionsForSubstring substring: String,
        indexOfToken tokenIndex: Int,
        indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?
    ) -> [Any]? {
        let query = substring.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            tokenField.tokenStyle = .none
            return []
        }

        var completions: [String] = []
        var seen = Set<String>()

        func append(_ value: String) {
            if seen.insert(value).inserted {
                completions.append(value)
            }
        }

        for contact in contactsCache ?? [] {
            let name = contactDisplayName(contact)
            let nameMatches = contactMatchesName(contact, query: query)

            for phone in contact.phoneNumbers {
                let number = phone.value.stringValue

                if phoneMatchesPrefix(number, query: query) {
                    append(name.isEmpty ? number : "\(number) (\(name))")
                }
                if nameMatches {
                    append(name.isEmpty ? number : "\(name) <\(number)>")
                }
            }

            for email in contact.emailAddresses {
                guard isSIPLabel(email.label) else { continue }
                let address = email.value as String

                if hasCaseInsensitivePrefix(address, query) {
                    append(name.isEmpty ? address : "\(address) (\(name))")
                }
                if nameMatches {
                    append(name.isEmpty ? address : "\(name) <\(address)>")
                }
            }
        }

        if let first = completions.first,
           let range = first.range(of: query, options: .caseInsensitive),
           range.lowerBound == first.startIndex {
            completions[0] = query + first[range.upperBound...]
        }

        tokenField.tokenStyle = completions.isEmpty ? .none : .rounded
        return completions
    }

    func tokenField(
        _ tokenField: NSTokenField,
        representedObjectForEditing editingString: String
    ) -> Any? {
        representedDestination(for: editingString)
    }

    func tokenField(
        _ tokenField: NSTokenField,
        displayStringForRepresentedObject representedObject: Any
    ) -> String? {
        guard
            let group = representedObject as? CallDestinationGroup,
            let uri = group.selectedDestination?.uri
        else {
            return nil
        }

        if !uri.displayName.isEmpty {
            return uri.displayName
        }
        if !uri.host.isEmpty {
            return uri.sipAddress
        }
        return formattedPhoneNumber(uri.user)
    }

    func tokenField(
        _ tokenField: NSTokenField,
        editingStringForRepresentedObject representedObject: Any
    ) -> String? {
        guard
            let group = representedObject as? CallDestinationGroup,
            let uri = group.selectedDestination?.uri
        else {
            return nil
        }

        if !uri.displayName.isEmpty {
            let destination = uri.host.isEmpty ? uri.user : uri.sipAddress
            return "\(uri.displayName) <\(destination)>"
        }
        return uri.host.isEmpty ? uri.user : uri.sipAddress
    }

    func tokenField(
        _ tokenField: NSTokenField,
        hasMenuForRepresentedObject representedObject: Any
    ) -> Bool {
        (representedObject as? CallDestinationGroup)?.destinations.count ?? 0 > 1
    }

    func tokenField(
        _ tokenField: NSTokenField,
        menuForRepresentedObject representedObject: Any
    ) -> NSMenu? {
        guard let group = representedObject as? CallDestinationGroup else { return nil }

        let menu = NSMenu()

        for (index, destination) in group.destinations.enumerated() {
            let uri = destination.uri
            let value: String

            if !uri.host.isEmpty {
                value = uri.sipAddress
            } else {
                value = formattedPhoneNumber(uri.user)
            }

            let label = destination.phoneLabel
            let item = NSMenuItem(
                title: label.isEmpty ? value : "\(label): \(value)",
                action: #selector(changeCallDestinationURIIndex(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = index == group.selectedIndex ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    func tokenField(
        _ tokenField: NSTokenField,
        shouldAdd objects: [Any],
        at index: Int
    ) -> [Any] {
        if index > 0 && tokenField.tokenStyle == .rounded {
            return []
        }
        return objects
    }
}

private struct ActiveAccountInputView: View {
    let field: NSTokenField

    var body: some View {
        TokenFieldView(field: field)
            .frame(minHeight: 24)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TokenFieldView: NSViewRepresentable {
    let field: NSTokenField

    func makeNSView(context: Context) -> NSTokenField {
        field
    }

    func updateNSView(_ nsView: NSTokenField, context: Context) {}
}
