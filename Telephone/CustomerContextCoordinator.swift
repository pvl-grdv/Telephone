//
//  CustomerContextCoordinator.swift
//  Telephone
//

import Foundation

@MainActor
final class CustomerContextCoordinator {
    private weak var callController: CallController?
    private let model: CallWindowModel
    private let crmProvider: any CRMProvider

    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var loadedKey: String?
    private var isApplyingSnapshot = false

    init(
        callController: CallController,
        model: CallWindowModel,
        crmProvider: any CRMProvider = DisabledCRMProvider()
    ) {
        self.callController = callController
        self.model = model
        self.crmProvider = crmProvider
    }

    func loadIfNeeded() {
        guard
            isEnabled,
            let callController,
            let address = partyAddress,
            !callController.identifier.isEmpty
        else {
            return
        }

        let callIdentifier = callController.identifier
        let key = "\(address.kind)|\(address.normalizedValue)|\(callIdentifier)"
        guard loadedKey != key else { return }

        loadTask?.cancel()
        loadedKey = key
        model.customerContextLoaded = false
        let displayName = customerDisplayName

        loadTask = Task { [weak self, crmProvider] in
            async let localSnapshot = CustomerContextStore.shared.load(
                address: address,
                displayName: displayName,
                callIdentifier: callIdentifier
            )
            async let crmProfile = crmProvider.customer(for: address)

            let snapshot = await localSnapshot
            let profile = await crmProfile

            guard
                !Task.isCancelled,
                let self,
                self.loadedKey == key
            else {
                return
            }

            self.isApplyingSnapshot = true
            self.model.customerCompany = snapshot.company.isEmpty
                ? self.model.contactOrganization
                : snapshot.company
            self.model.customerKeys = snapshot.keys.joined(separator: ", ")
            self.model.customerEmails = snapshot.emails.joined(separator: ", ")
            self.model.customerNote = snapshot.currentCallNote
            self.model.previousConversationCount =
                snapshot.previousConversationCount
            self.model.lastCallDate = snapshot.lastCallDate
            self.model.recentCustomerNotes = snapshot.recentNotes
            self.model.crmProfile = profile

            if let profile, profile.hasContent {
                let identity = CallerIdentityPresentation.promotingCompany(
                    profile.company,
                    currentPrimary: self.model.displayedName,
                    currentDetail: self.model.identityDetail
                )
                self.model.displayedName = identity.primary
                self.model.identityDetail = identity.detail
            }

            self.model.customerContextLoaded = true
            self.isApplyingSnapshot = false
        }
    }

    func scheduleSave() {
        guard
            isEnabled,
            model.customerContextLoaded,
            !isApplyingSnapshot
        else {
            return
        }

        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }

            self?.saveNow()
        }
    }

    func visibilityChanged(_ isVisible: Bool) {
        if isVisible {
            loadIfNeeded()
        } else {
            saveNow(ignoringPreference: true)
            loadTask?.cancel()
            loadTask = nil
            loadedKey = nil
            model.customerContextLoaded = false
            model.crmProfile = nil
        }
    }

    func saveNow(ignoringPreference: Bool = false) {
        guard
            (ignoringPreference || isEnabled),
            model.customerContextLoaded,
            !isApplyingSnapshot,
            let callController,
            let address = partyAddress,
            !callController.identifier.isEmpty
        else {
            return
        }

        saveTask?.cancel()
        saveTask = nil

        let callIdentifier = callController.identifier
        let displayName = customerDisplayName
        let company = model.customerCompany
        let keys = listValues(model.customerKeys)
        let emails = listValues(model.customerEmails)
        let note = model.customerNote

        Task {
            await CustomerContextStore.shared.save(
                address: address,
                displayName: displayName,
                callIdentifier: callIdentifier,
                company: company,
                keys: keys,
                emails: emails,
                note: note
            )
        }
    }

    func invalidate() {
        loadTask?.cancel()
        loadTask = nil
        saveTask?.cancel()
        saveTask = nil
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(
            forKey: UserDefaultsKeys.showCustomerContext
        ) as? Bool ?? true
    }

    private var partyAddress: CustomerPartyAddress? {
        guard let callController else { return nil }

        if let uri = callController.call?.remoteURI ?? callController.redialURI {
            return CustomerPartyAddress(user: uri.user, host: uri.host)
        }

        let entered = callController.enteredCallDestination?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !entered.isEmpty else { return nil }
        return CustomerPartyAddress(user: entered, host: "")
    }

    private var customerDisplayName: String {
        guard let callController else { return "" }

        let addressBookName = callController.nameFromAddressBook ?? ""
        if !addressBookName.isEmpty {
            return addressBookName
        }

        return callController.displayedName ?? ""
    }

    private func listValues(_ text: String) -> [String] {
        text.split { character in
            character == "," || character == ";" || character.isNewline
        }
        .map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    }
}
