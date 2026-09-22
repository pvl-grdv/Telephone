//
//  ActiveAccountViewController.swift
//  Telephone
//

import AppKit
@preconcurrency import Contacts
import Observation
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

    override func isEqual(_ object: Any?) -> Bool {
        if self === object as AnyObject? {
            return true
        }
        guard let other = object as? CallDestination else {
            return false
        }
        return uri.isEqual(other.uri) && phoneLabel == other.phoneLabel
    }

    override var hash: Int {
        var result = uri.hash
        result = result &* 31 &+ phoneLabel.hashValue
        return result
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

    override func isEqual(_ object: Any?) -> Bool {
        if self === object as AnyObject? {
            return true
        }
        guard
            let other = object as? CallDestinationGroup,
            selectedIndex == other.selectedIndex,
            destinations.count == other.destinations.count
        else {
            return false
        }

        return zip(destinations, other.destinations).allSatisfy { left, right in
            left.isEqual(right)
        }
    }

    override var hash: Int {
        var result = selectedIndex.hashValue
        for destination in destinations {
            result = result &* 31 &+ destination.hash
        }
        return result
    }
}

private struct ContactCachePayload: @unchecked Sendable {
    let contacts: [CNContact]
}

private struct CallDestinationSuggestion: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let editingText: String
    let group: CallDestinationGroup
}

private struct CallDestinationOption: Identifiable {
    let id: Int
    let title: String
    let isSelected: Bool
}

@MainActor
@Observable
private final class CallDestinationInputModel {
    var text = "" {
        didSet {
            guard !isApplyingSelection else { return }
            selectedGroup = nil
            refreshSuggestions()
        }
    }
    var isVisible = false
    var isFocused = false
    var focusRequest = 0
    var suggestions: [CallDestinationSuggestion] = []
    var highlightedSuggestionID: String?

    @ObservationIgnored private let contactStore = CNContactStore()
    @ObservationIgnored private var contactsCache: [CNContact]?
    @ObservationIgnored private var contactsCacheLoading = false
    @ObservationIgnored private var contactsPermissionRequestInFlight = false
    @ObservationIgnored private var isApplyingSelection = false
    @ObservationIgnored private var selectedGroup: CallDestinationGroup?

    var canCall: Bool {
        selectedGroup != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasMultipleDestinations: Bool {
        (selectedGroup?.destinations.count ?? 0) > 1
    }

    var destinationOptions: [CallDestinationOption] {
        guard let group = selectedGroup else { return [] }

        return group.destinations.enumerated().map { index, destination in
            let uri = destination.uri
            let value = uri.host.isEmpty
                ? formattedPhoneNumber(uri.user)
                : uri.sipAddress
            let label = destination.phoneLabel
            return CallDestinationOption(
                id: index,
                title: label.isEmpty ? value : "\(label): \(value)",
                isSelected: index == group.selectedIndex
            )
        }
    }

    var callDestinationURI: AKSIPURI? {
        if selectedGroup == nil {
            normalizeCurrentDestination()
        }
        guard
            let uri = selectedGroup?.selectedDestination?.uri.copy() as? AKSIPURI,
            !uri.user.isEmpty
        else {
            return nil
        }
        return uri
    }

    var callDestinationPhoneLabel: String {
        if selectedGroup == nil {
            normalizeCurrentDestination()
        }
        return selectedGroup?.selectedDestination?.phoneLabel ?? ""
    }

    init() {
        if CNContactStore.authorizationStatus(for: .contacts) == .authorized {
            refreshContactsCache()
        }
    }

    func setFocused(_ focused: Bool) {
        isFocused = focused

        if focused {
            requestContactsAccessIfNeeded()
            refreshSuggestions()
        } else {
            dismissSuggestions()
        }
    }

    func requestFocus() {
        focusRequest &+= 1
    }

    func setDestination(_ destination: String) {
        isApplyingSelection = true
        text = destination
        isApplyingSelection = false
        normalizeCurrentDestination()
    }

    func chooseSuggestion(_ suggestion: CallDestinationSuggestion) {
        applySelection(group: suggestion.group, editingText: suggestion.editingText)
    }

    func selectDestination(at index: Int) {
        guard
            let group = selectedGroup,
            group.destinations.indices.contains(index)
        else {
            return
        }

        let replacement = CallDestinationGroup(
            destinations: group.destinations,
            selectedIndex: index
        )
        applySelection(
            group: replacement,
            editingText: editingString(for: replacement)
        )
    }

    func moveSuggestionSelection(by delta: Int) {
        guard !suggestions.isEmpty else { return }

        let currentIndex = highlightedSuggestionID.flatMap { id in
            suggestions.firstIndex { $0.id == id }
        } ?? (delta > 0 ? -1 : 0)

        let nextIndex = min(
            suggestions.count - 1,
            max(0, currentIndex + delta)
        )
        highlightedSuggestionID = suggestions[nextIndex].id
    }

    func highlightSuggestion(_ id: String) {
        highlightedSuggestionID = id
    }

    func acceptHighlightedSuggestion() -> Bool {
        guard
            let highlightedSuggestionID,
            let suggestion = suggestions.first(where: { $0.id == highlightedSuggestionID })
        else {
            return false
        }

        chooseSuggestion(suggestion)
        return true
    }

    func dismissSuggestions() {
        suggestions = []
        highlightedSuggestionID = nil
    }

    private func applySelection(group: CallDestinationGroup, editingText: String) {
        selectedGroup = group
        isApplyingSelection = true
        text = editingText
        isApplyingSelection = false
        dismissSuggestions()
    }

    private func normalizeCurrentDestination() {
        guard let represented = representedDestination(for: text) else {
            selectedGroup = nil
            return
        }
        selectedGroup = represented
        isApplyingSelection = true
        text = editingString(for: represented)
        isApplyingSelection = false
        dismissSuggestions()
    }

    private func refreshSuggestions() {
        guard isFocused else {
            dismissSuggestions()
            return
        }

        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            dismissSuggestions()
            return
        }

        var values: [CallDestinationSuggestion] = []
        var seen = Set<String>()

        for contact in contactsCache ?? [] {
            let displayName = contactDisplayName(contact)
            let nameMatches = contactMatchesName(contact, query: query)
            let destinations = destinations(for: contact, displayName: displayName)

            for (index, destination) in destinations.enumerated() {
                let uri = destination.uri
                let address = uri.host.isEmpty ? uri.user : uri.sipAddress
                let addressMatches: Bool

                if uri.host.isEmpty {
                    addressMatches = phoneMatchesPrefix(address, query: query)
                } else {
                    addressMatches = hasCaseInsensitivePrefix(address, query)
                }

                guard nameMatches || addressMatches else { continue }

                let id = "\(contact.identifier)|\(index)|\(address)"
                guard seen.insert(id).inserted else { continue }

                let value = uri.host.isEmpty
                    ? formattedPhoneNumber(uri.user)
                    : uri.sipAddress
                let subtitle = destination.phoneLabel.isEmpty
                    ? value
                    : "\(destination.phoneLabel) · \(value)"
                let group = CallDestinationGroup(
                    destinations: destinations,
                    selectedIndex: index
                )
                let editingText = displayName.isEmpty
                    ? address
                    : "\(displayName) <\(address)>"

                values.append(
                    CallDestinationSuggestion(
                        id: id,
                        title: displayName.isEmpty ? value : displayName,
                        subtitle: subtitle,
                        editingText: editingText,
                        group: group
                    )
                )

                if values.count == 5 {
                    break
                }
            }

            if values.count == 5 {
                break
            }
        }

        suggestions = values
        highlightedSuggestionID = values.first?.id
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
                self.refreshSuggestions()
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

    private func representedDestination(for editingString: String) -> CallDestinationGroup? {
        let trimmed = editingString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uri = parseURI(trimmed), !uri.user.isEmpty else { return nil }

        let contact = matchingContact(
            for: uri,
            displayedName: uri.displayName,
            contacts: contactsCache ?? []
        )

        if let contact {
            let displayName = contactDisplayName(contact)
            if !displayName.isEmpty {
                uri.displayName = displayName
            }

            let destinations = destinations(for: contact, displayName: uri.displayName)
            let selectedIndex = selectedIndex(
                in: destinations,
                matching: uri
            )

            if !destinations.isEmpty {
                return CallDestinationGroup(
                    destinations: destinations,
                    selectedIndex: selectedIndex
                )
            }
        }

        return CallDestinationGroup(
            destinations: [CallDestination(uri: uri, phoneLabel: "")],
            selectedIndex: 0
        )
    }

    private func destinations(
        for contact: CNContact,
        displayName: String
    ) -> [CallDestination] {
        var destinations: [CallDestination] = []

        for phone in contact.phoneNumbers {
            guard let candidate = parseURI(phone.value.stringValue) else { continue }
            candidate.displayName = displayName
            destinations.append(
                CallDestination(
                    uri: candidate,
                    phoneLabel: localizedContactLabel(phone.label)
                )
            )
        }

        for email in contact.emailAddresses {
            guard isSIPLabel(email.label) else { continue }

            let address = email.value as String
            guard let candidate = parseURI(address) else { continue }
            candidate.displayName = displayName
            destinations.append(
                CallDestination(
                    uri: candidate,
                    phoneLabel: localizedContactLabel(email.label)
                )
            )
        }

        return destinations
    }

    private func selectedIndex(
        in destinations: [CallDestination],
        matching uri: AKSIPURI
    ) -> Int {
        if uri.host.isEmpty {
            let targetPhone = normalizedPhoneNumber(uri.user)
            if let match = destinations.firstIndex(where: {
                $0.uri.host.isEmpty
                    && normalizedPhoneNumber($0.uri.user) == targetPhone
            }) {
                return match
            }
        } else if let match = destinations.firstIndex(where: {
            !$0.uri.host.isEmpty
                && $0.uri.sipAddress.caseInsensitiveCompare(uri.sipAddress) == .orderedSame
        }) {
            return match
        }

        return 0
    }

    private func editingString(for group: CallDestinationGroup) -> String {
        guard let uri = group.selectedDestination?.uri else { return text }

        let destination = uri.host.isEmpty ? uri.user : uri.sipAddress
        return uri.displayName.isEmpty
            ? destination
            : "\(uri.displayName) <\(destination)>"
    }

    private func parseURI(_ string: String) -> AKSIPURI? {
        let formatter = configuredSIPFormatter()
        var object: AnyObject?
        var error: NSString?

        guard formatter.getObjectValue(
            &object,
            for: string,
            errorDescription: &error
        ) else {
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
        formatter.formatsTelephoneNumbers =
            defaults.bool(forKey: UserDefaultsKeys.formatTelephoneNumbers)
        formatter.telephoneNumberFormatterSplitsLastFourDigits =
            defaults.bool(
                forKey: UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits
            )
        return formatter
    }

    private func formattedPhoneNumber(_ value: String) -> String {
        let formatter = AKTelephoneNumberFormatter()
        formatter.splitsLastFourDigits =
            UserDefaults.standard.bool(
                forKey: UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits
            )
        return formatter.string(for: value) ?? value
    }

    private func normalizedPhoneNumber(_ value: String) -> String {
        value.filter { $0.isNumber || $0 == "+" }
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
}

@MainActor
@objcMembers
class ActiveAccountViewController: NSViewController {
    private weak var storedAccountController: AccountController?
    fileprivate let inputModel = CallDestinationInputModel()

    var accountController: AccountController? {
        storedAccountController
    }

    var callDestinationURI: AKSIPURI? {
        inputModel.callDestinationURI
    }

    var callDestinationPhoneLabel: String {
        inputModel.callDestinationPhoneLabel
    }

    var allowsCallDestinationInput: Bool {
        inputModel.isVisible
    }

    @nonobjc var contentView: AnyView {
        destinationInputView(
            showsCallButton: true,
            call: { [weak self] in self?.makeCall(nil) }
        )
    }

    @objc(initWithAccountController:)
    init(accountController: AccountController) {
        storedAccountController = accountController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSHostingView(rootView: contentView)
    }

    @IBAction func makeCall(_ sender: Any?) {
        guard let uri = callDestinationURI else { return }
        storedAccountController?.makeCall(
            to: uri,
            phoneLabel: callDestinationPhoneLabel
        )
    }

    func makeCallToDestination(_ destination: String) {
        inputModel.setDestination(destination)
        makeCall(self)
    }

    func allowCallDestinationInput() {
        inputModel.isVisible = true
        inputModel.requestFocus()
    }

    func disallowCallDestinationInput() {
        inputModel.isVisible = false
        inputModel.setFocused(false)
    }

    func focusCallDestination() {
        inputModel.requestFocus()
    }

    @nonobjc func destinationInputView(
        showsCallButton: Bool,
        call: @escaping () -> Void
    ) -> AnyView {
        AnyView(
            CallDestinationInputView(
                model: inputModel,
                showsCallButton: showsCallButton,
                call: call
            )
        )
    }
}

private struct CallDestinationInputView: View {
    @Bindable var model: CallDestinationInputModel
    @FocusState private var inputFocused: Bool

    let showsCallButton: Bool
    let call: () -> Void

    private var showsSuggestions: Bool {
        inputFocused && !model.suggestions.isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField(
                    NSLocalizedString(
                        "Phone number or SIP address",
                        comment: "Call destination field placeholder."
                    ),
                    text: $model.text
                )
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onSubmit {
                    if !model.acceptHighlightedSuggestion() {
                        call()
                    }
                }
                .onKeyPress(.downArrow) {
                    model.moveSuggestionSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    model.moveSuggestionSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    model.dismissSuggestions()
                    return .handled
                }

                if model.hasMultipleDestinations {
                    Menu {
                        ForEach(model.destinationOptions) { option in
                            Button {
                                model.selectDestination(at: option.id)
                            } label: {
                                if option.isSelected {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .help(
                        NSLocalizedString(
                            "Choose Destination",
                            comment: "Choose a contact destination."
                        )
                    )
                    .accessibilityLabel(
                        NSLocalizedString(
                            "Choose Destination",
                            comment: "Choose a contact destination."
                        )
                    )
                }

                if showsCallButton {
                    Button(action: call) {
                        Image(systemName: "phone.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!model.canCall)
                    .help(NSLocalizedString("Call", comment: "Call button."))
                    .accessibilityLabel(
                        NSLocalizedString("Call", comment: "Call button.")
                    )
                }
            }

            if showsSuggestions {
                DestinationSuggestionsView(
                    suggestions: model.suggestions,
                    highlightedID: model.highlightedSuggestionID,
                    choose: model.chooseSuggestion,
                    hover: model.highlightSuggestion
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .onAppear {
            if model.isVisible {
                inputFocused = true
            }
        }
        .onChange(of: inputFocused) {
            model.setFocused(inputFocused)
        }
        .onChange(of: model.focusRequest) {
            inputFocused = true
        }
        .animation(.easeInOut(duration: 0.12), value: showsSuggestions)
    }
}

private struct DestinationSuggestionsView: View {
    let suggestions: [CallDestinationSuggestion]
    let highlightedID: String?
    let choose: (CallDestinationSuggestion) -> Void
    let hover: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    choose(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.title)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Text(suggestion.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .background {
                        if highlightedID == suggestion.id {
                            Color.accentColor.opacity(0.12)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        hover(suggestion.id)
                    }
                }

                if suggestion.id != suggestions.last?.id {
                    Divider()
                        .padding(.leading, 38)
                }
            }
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(.separator.opacity(0.6), lineWidth: 0.5)
        }
        .shadow(radius: 5, y: 2)
    }
}
