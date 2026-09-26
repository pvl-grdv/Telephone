//
//  CallDestinationComposer.swift
//  Telephone
//

import Foundation
@preconcurrency import Contacts
import Observation
import SwiftUI

extension Notification.Name {
    static let AKContactsAuthorizationDidChange =
        Notification.Name("TelephoneContactsAuthorizationDidChange")
}

private struct CallDestination {
    let uri: AKSIPURI
    let phoneLabel: String
}

private struct CallDestinationGroup {
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

private struct CallDestinationSuggestionMatch: Sendable {
    let contact: CallDestinationContactRecord
    let destination: CallDestinationContactAddress
}

@MainActor
@Observable
private final class CallDestinationInputModel {
    private static let contactStore = CNContactStore()

    var text = "" {
        didSet {
            guard !isApplyingSelection else { return }
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

    @ObservationIgnored
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
            let uri = selectedGroup?.selectedDestination?.uri.copy()
                as? AKSIPURI,
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

    func setFocused(_ focused: Bool) {
        isFocused = focused

        if focused {
            requestContactsAccessIfNeeded()
            refreshSuggestions()
        } else {
            suggestionTask?.cancel()
            suggestionTask = nil
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
        suggestionTask?.cancel()
        suggestionTask = nil

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

        let task = Task.detached(priority: .userInitiated) {
            Self.suggestionMatches(
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

    nonisolated private static func suggestionMatches(
        contacts: [CallDestinationContactRecord],
        query: String,
        limit: Int
    ) -> [CallDestinationSuggestionMatch] {
        var matches: [CallDestinationSuggestionMatch] = []
        var seen = Set<String>()

        for contact in contacts {
            guard !Task.isCancelled else { return [] }

            let nameMatches = contactMatchesName(
                contact,
                query: query
            )

            for destination in contact.destinations {
                let addressMatches: Bool
                switch destination.kind {
                case .phone:
                    addressMatches = phoneMatchesPrefix(
                        destination.value,
                        query: query
                    )
                case .sip:
                    addressMatches = hasCaseInsensitivePrefix(
                        destination.value,
                        query
                    )
                }

                guard nameMatches || addressMatches else { continue }

                let key =
                    "\(contact.id)|\(destination.kind)|\(destination.value)"
                guard seen.insert(key).inserted else { continue }

                matches.append(
                    CallDestinationSuggestionMatch(
                        contact: contact,
                        destination: destination
                    )
                )
                if matches.count == limit {
                    return matches
                }
            }
        }

        return matches
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
                        NSLog(
                            "Could not get Contacts access: %@",
                            error.localizedDescription
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
            let targetPhone = Self.normalizedPhoneNumber(uri.user)
            if let match = destinations.firstIndex(where: {
                $0.uri.host.isEmpty
                    && Self.normalizedPhoneNumber($0.uri.user) == targetPhone
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

    nonisolated private static func normalizedPhoneNumber(
        _ value: String
    ) -> String {
        value.filter { $0.isNumber || $0 == "+" }
    }

    nonisolated private static func hasCaseInsensitivePrefix(
        _ value: String,
        _ prefix: String
    ) -> Bool {
        guard !value.isEmpty, !prefix.isEmpty else { return false }
        return value.range(
            of: prefix,
            options: [.caseInsensitive, .anchored]
        ) != nil
    }

    nonisolated private static func contactMatchesName(
        _ contact: CallDestinationContactRecord,
        query: String
    ) -> Bool {
        let givenFamily = "\(contact.givenName) \(contact.familyName)"
        let familyGiven = "\(contact.familyName) \(contact.givenName)"

        return hasCaseInsensitivePrefix(contact.displayName, query)
            || hasCaseInsensitivePrefix(contact.givenName, query)
            || hasCaseInsensitivePrefix(contact.familyName, query)
            || hasCaseInsensitivePrefix(givenFamily, query)
            || hasCaseInsensitivePrefix(familyGiven, query)
            || hasCaseInsensitivePrefix(contact.organizationName, query)
    }

    nonisolated private static func phoneMatchesPrefix(
        _ phoneNumber: String,
        query: String
    ) -> Bool {
        let normalizedPhone = normalizedPhoneNumber(phoneNumber)
        let normalizedQuery = normalizedPhoneNumber(query)
        return !normalizedQuery.isEmpty
            && normalizedPhone.hasPrefix(normalizedQuery)
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
                let target = Self.normalizedPhoneNumber(uri.user)
                addressMatches = contact.destinations.contains {
                    $0.kind == .phone
                        && !target.isEmpty
                        && Self.normalizedPhoneNumber($0.value) == target
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

@MainActor
final class CallDestinationComposer {
    private weak var accountController: AccountController?
    fileprivate let inputModel = CallDestinationInputModel()

    var callDestinationURI: AKSIPURI? {
        inputModel.callDestinationURI
    }

    var callDestinationPhoneLabel: String {
        inputModel.callDestinationPhoneLabel
    }

    var contentView: some View {
        inputView(
            showsCallButton: true,
            call: { [weak self] in
                self?.makeCall()
            }
        )
    }

    init(accountController: AccountController) {
        self.accountController = accountController
    }

    func makeCall(callTransferController: CallTransferController? = nil) {
        guard let uri = callDestinationURI else { return }

        if let callTransferController {
            accountController?.makeCall(
                to: uri,
                phoneLabel: callDestinationPhoneLabel,
                callTransferController: callTransferController
            )
        } else {
            accountController?.makeCall(
                to: uri,
                phoneLabel: callDestinationPhoneLabel
            )
        }
    }

    func makeCallToDestination(_ destination: String) {
        inputModel.setDestination(destination)
        makeCall()
    }

    func focus() {
        inputModel.requestFocus()
    }

    func inputView(
        showsCallButton: Bool,
        call: @escaping () -> Void
    ) -> some View {
        CallDestinationInputView(
            model: inputModel,
            showsCallButton: showsCallButton,
            call: call
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
            inputRow

            if showsSuggestions {
                DestinationSuggestionsView(
                    suggestions: model.suggestions,
                    highlightedID: model.highlightedSuggestionID,
                    choose: model.chooseSuggestion,
                    hover: model.highlightSuggestion
                )
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .defaultFocus($inputFocused, true)
        .onDisappear {
            model.setFocused(false)
        }
        .onChange(of: inputFocused) {
            model.setFocused(inputFocused)
        }
        .onChange(of: model.focusRequest) {
            inputFocused = true
        }
        .animation(.easeInOut(duration: 0.12), value: showsSuggestions)
    }

    private var inputRow: some View {
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
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
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
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.canCall)
                .help(NSLocalizedString("Call", comment: "Call button."))
                .accessibilityLabel(
                    NSLocalizedString("Call", comment: "Call button.")
                )
            }
        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(.separator.opacity(0.6), lineWidth: 0.5)
        }
        .shadow(radius: 5, y: 2)
    }
}


struct TransferDestinationView: View {
    let composer: CallDestinationComposer
    let call: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                NSLocalizedString(
                    "Transfer to:",
                    comment: "Call transfer destination label."
                )
            )
            .font(.headline)

            composer.inputView(
                showsCallButton: false,
                call: call
            )

            HStack {
                Spacer()

                Button(
                    NSLocalizedString("Close", comment: "Close button."),
                    action: close
                )
                .keyboardShortcut(.cancelAction)

                Button(
                    NSLocalizedString("Call", comment: "Call button."),
                    action: call
                )
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 320, idealWidth: 360, minHeight: 118)
    }
}
