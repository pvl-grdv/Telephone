//
//  CallDestinationInputModel.swift
//  Telephone
//

import Foundation
@preconcurrency import Contacts
import Observation

extension Notification.Name {
    static let AKContactsAuthorizationDidChange =
        Notification.Name("TelephoneContactsAuthorizationDidChange")
}

struct CallDestination {
    let uri: AKSIPURI
    let phoneLabel: String
}

struct CallDestinationGroup {
    let destinations: [CallDestination]
    let selectedIndex: Int

    var selectedDestination: CallDestination? {
        guard destinations.indices.contains(selectedIndex) else { return nil }
        return destinations[selectedIndex]
    }

    init(destinations: [CallDestination], selectedIndex: Int) {
        self.destinations = destinations
        self.selectedIndex = destinations.indices.contains(selectedIndex) ? selectedIndex : 0
    }
}

struct CallDestinationSuggestion: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let editingText: String
    let group: CallDestinationGroup
}

struct CallDestinationOption: Identifiable {
    let id: Int
    let title: String
    let isSelected: Bool
}

@MainActor
@Observable
final class CallDestinationInputModel {
    private static let contactStore = CNContactStore()

    var text = "" {
        didSet {
            guard oldValue != text, !isApplyingSelection else { return }
            selectedGroup = nil
            refreshSuggestions()
        }
    }
    var isFocused = false
    var focusRequest = 0
    var suggestions: [CallDestinationSuggestion] = []
    var highlightedSuggestionID: String?

    @ObservationIgnored
    private var contactsCache: [CallDestinationContactRecord]?

    @ObservationIgnored
    private var contactsCacheLoading = false

    @ObservationIgnored
    private var contactsPermissionRequestInFlight = false

    @ObservationIgnored
    private var suggestionTask:
        Task<[CallDestinationSuggestionMatch], Never>?

    @ObservationIgnored
    private var isApplyingSelection = false

    // The destination menu reads this value directly; it must be observed.
    private var selectedGroup: CallDestinationGroup?

    var canCall: Bool {
        selectedGroup != nil
            || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            let source = selectedGroup?.selectedDestination?.uri,
            !source.user.isEmpty
        else {
            return nil
        }

        return AKSIPURI(
            user: source.user,
            host: source.host,
            displayName: source.displayName,
            port: source.port
        )
    }

    var callDestinationPhoneLabel: String {
        if selectedGroup == nil {
            normalizeCurrentDestination()
        }
        return selectedGroup?.selectedDestination?.phoneLabel ?? ""
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
        updateTextWithoutRefreshing(destination)
        normalizeCurrentDestination()
    }

    func chooseSuggestion(_ suggestion: CallDestinationSuggestion) {
        applySelection(
            group: suggestion.group,
            editingText: suggestion.editingText
        )
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
            let suggestion = suggestions.first(where: {
                $0.id == highlightedSuggestionID
            })
        else {
            return false
        }

        chooseSuggestion(suggestion)
        return true
    }

    func dismissSuggestions() {
        suggestionTask?.cancel()
        suggestionTask = nil
        suggestions = []
        highlightedSuggestionID = nil
    }

    private func applySelection(
        group: CallDestinationGroup,
        editingText: String
    ) {
        selectedGroup = group
        updateTextWithoutRefreshing(editingText)
        dismissSuggestions()
    }

    /// Programmatic changes must not be mistaken for new user input.
    private func updateTextWithoutRefreshing(_ value: String) {
        isApplyingSelection = true
        text = value
        isApplyingSelection = false
    }

    private func normalizeCurrentDestination() {
        guard let represented = representedDestination(for: text) else {
            selectedGroup = nil
            return
        }
        applySelection(
            group: represented,
            editingText: editingString(for: represented)
        )
    }

    private func refreshSuggestions() {
        guard isFocused else {
            dismissSuggestions()
            return
        }

        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !query.isEmpty,
            let contactsCache
        else {
            dismissSuggestions()
            return
        }

        suggestionTask?.cancel()
        let task = Task.detached(priority: .userInitiated) {
            CallDestinationContactMatching.suggestions(
                contacts: contactsCache,
                query: query,
                limit: 5
            )
        }
        suggestionTask = task

        Task { [weak self] in
            let matches = await task.value

            guard
                !task.isCancelled,
                let self,
                self.isFocused,
                self.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) == query
            else {
                return
            }

            self.suggestionTask = nil
            self.applySuggestionMatches(matches)
        }
    }

    private func applySuggestionMatches(
        _ matches: [CallDestinationSuggestionMatch]
    ) {
        var values: [CallDestinationSuggestion] = []

        for match in matches {
            let contact = match.contact
            let displayName = contact.displayName
            let destinations = destinations(
                for: contact,
                displayName: displayName
            )

            guard
                !destinations.isEmpty,
                let selectedURI = parseURI(match.destination.value)
            else {
                continue
            }

            selectedURI.displayName = displayName
            let selectedIndex = selectedIndex(
                in: destinations,
                matching: selectedURI
            )
            let selected = destinations[selectedIndex]
            let uri = selected.uri
            let address = uri.host.isEmpty ? uri.user : uri.sipAddress
            let value = uri.host.isEmpty
                ? formattedPhoneNumber(uri.user)
                : uri.sipAddress
            let subtitle = selected.phoneLabel.isEmpty
                ? value
                : "\(selected.phoneLabel) · \(value)"
            let group = CallDestinationGroup(
                destinations: destinations,
                selectedIndex: selectedIndex
            )
            let editingText = displayName.isEmpty
                ? address
                : "\(displayName) <\(address)>"

            values.append(
                CallDestinationSuggestion(
                    id: "\(contact.id)|\(match.destination.kind)|\(match.destination.value)",
                    title: displayName.isEmpty ? value : displayName,
                    subtitle: subtitle,
                    editingText: editingText,
                    group: group
                )
            )
        }

        suggestions = values
        highlightedSuggestionID = values.first?.id
    }

    private func requestContactsAccessIfNeeded() {
        let status = CNContactStore.authorizationStatus(for: .contacts)

        if status == .authorized {
            refreshContactsCache()
            return
        }

        contactsCache = nil
        dismissSuggestions()

        guard
            status == .notDetermined,
            !contactsPermissionRequestInFlight
        else {
            return
        }

        contactsPermissionRequestInFlight = true
        Self.contactStore.requestAccess(
            for: .contacts
        ) { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }

                self.contactsPermissionRequestInFlight = false
                guard granted else {
                    if let error {
                        let nsError = error as NSError
                        Log.callDestination.error(
                            """
                            Could not get Contacts access \
                            domain=\(nsError.domain, privacy: .public) \
                            code=\(nsError.code, privacy: .public) \
                            description=\(nsError.localizedDescription, privacy: .private)
                            """
                        )
                    }
                    return
                }

                self.refreshContactsCache(forceReload: true)
                NotificationCenter.default.post(
                    name: .AKContactsAuthorizationDidChange,
                    object: nil
                )
            }
        }
    }

    private func refreshContactsCache(
        forceReload: Bool = false
    ) {
        guard !contactsCacheLoading else { return }

        contactsCacheLoading = true

        Task { [weak self] in
            let records = await CallDestinationContactIndex.shared.records(
                forceReload: forceReload
            )

            guard let self else { return }

            contactsCache = records
            contactsCacheLoading = false
            refreshSuggestions()
        }
    }

    private func representedDestination(
        for editingString: String
    ) -> CallDestinationGroup? {
        let trimmed = editingString.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let uri = parseURI(trimmed), !uri.user.isEmpty else {
            return nil
        }

        let contact = matchingContact(
            for: uri,
            displayedName: uri.displayName,
            contacts: contactsCache ?? []
        )

        if let contact {
            let displayName = contact.displayName
            if !displayName.isEmpty {
                uri.displayName = displayName
            }

            let destinations = destinations(
                for: contact,
                displayName: uri.displayName
            )
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
            destinations: [
                CallDestination(
                    uri: uri,
                    phoneLabel: ""
                )
            ],
            selectedIndex: 0
        )
    }

    private func destinations(
        for contact: CallDestinationContactRecord,
        displayName: String
    ) -> [CallDestination] {
        contact.destinations.compactMap { destination in
            guard let candidate = parseURI(destination.value) else {
                return nil
            }
            candidate.displayName = displayName
            return CallDestination(
                uri: candidate,
                phoneLabel: destination.label
            )
        }
    }

    private func selectedIndex(
        in destinations: [CallDestination],
        matching uri: AKSIPURI
    ) -> Int {
        if uri.host.isEmpty {
            let targetPhone = CallDestinationContactMatching.normalizedPhoneNumber(uri.user)
            if let match = destinations.firstIndex(where: {
                $0.uri.host.isEmpty
                    && CallDestinationContactMatching.normalizedPhoneNumber($0.uri.user) == targetPhone
            }) {
                return match
            }
        } else if let match = destinations.firstIndex(where: {
            !$0.uri.host.isEmpty
                && $0.uri.sipAddress.caseInsensitiveCompare(
                    uri.sipAddress
                ) == .orderedSame
        }) {
            return match
        }

        return 0
    }

    private func editingString(
        for group: CallDestinationGroup
    ) -> String {
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
                Log.callDestination.debug(
                    "Could not parse call destination: \(error as String, privacy: .private)"
                )
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
                forKey:
                    UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits
            )
        return formatter
    }

    private func formattedPhoneNumber(_ value: String) -> String {
        let formatter = AKTelephoneNumberFormatter()
        formatter.splitsLastFourDigits =
            UserDefaults.standard.bool(
                forKey:
                    UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits
            )
        return formatter.string(for: value) ?? value
    }

    private func contactNameEquals(
        _ contact: CallDestinationContactRecord,
        name: String
    ) -> Bool {
        guard !name.isEmpty else { return true }
        return contact.displayName.caseInsensitiveCompare(name) == .orderedSame
            || contact.organizationName.caseInsensitiveCompare(name)
                == .orderedSame
    }

    private func matchingContact(
        for uri: AKSIPURI,
        displayedName: String,
        contacts: [CallDestinationContactRecord]
    ) -> CallDestinationContactRecord? {
        var fallback: CallDestinationContactRecord?

        for contact in contacts {
            let addressMatches: Bool

            if uri.host.isEmpty {
                let target = CallDestinationContactMatching.normalizedPhoneNumber(uri.user)
                addressMatches = contact.destinations.contains {
                    $0.kind == .phone
                        && !target.isEmpty
                        && CallDestinationContactMatching.normalizedPhoneNumber($0.value) == target
                }
            } else {
                let target = uri.sipAddress
                addressMatches = contact.destinations.contains {
                    $0.kind == .sip
                        && $0.value.caseInsensitiveCompare(target)
                            == .orderedSame
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

