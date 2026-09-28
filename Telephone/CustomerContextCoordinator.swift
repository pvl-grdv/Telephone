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
    private var saveDebounceTask: Task<Void, Never>?
    private var saveTail: Task<Void, Never>?
    private var saveGeneration = 0
    private var loadedKey: String?
    private var loadedAddress: CustomerPartyAddress?
    private var loadedDisplayName = ""
    private var callIdentifier = UUID().uuidString
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

        let contextIdentifier = callIdentifier
        let key = "\(address.kind)|\(address.normalizedValue)|\(callIdentifier)"
        guard loadedKey != key else { return }

        loadTask?.cancel()
        loadedKey = key
        loadedAddress = address
        let displayName = customerDisplayName
        loadedDisplayName = displayName
        model.customerContextLoaded = false
        model.customerContextLoadFailed = false
        model.customerContextSaveSucceeded = false

        loadTask = Task { [weak self, crmProvider] in
            async let localResult = CustomerContextStore.shared.load(
                address: address,
                displayName: displayName,
                callIdentifier: contextIdentifier
            )
            async let crmProfile = crmProvider.customer(for: address)

            let result = await localResult

            guard
                !Task.isCancelled,
                let self,
                self.loadedKey == key
            else {
                return
            }

            switch result {
            case .success(let snapshot):
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
                self.model.customerContextLoaded = true
                self.model.customerContextLoadFailed = false
                self.isApplyingSnapshot = false
            case .failure:
                self.model.customerContextLoaded = false
                self.model.customerContextLoadFailed = true
                return
            }

            let profile = await crmProfile

            guard
                !Task.isCancelled,
                self.loadedKey == key
            else {
                return
            }

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
        }
    }

    func reload() {
        loadedKey = nil
        loadIfNeeded()
    }

    func callDidChange() {
        saveNow(ignoringPreference: true)

        loadTask?.cancel()
        loadTask = nil
        saveDebounceTask?.cancel()
        saveDebounceTask = nil

        loadedKey = nil
        loadedAddress = nil
        loadedDisplayName = ""
        callIdentifier = UUID().uuidString
        resetPresentation()
    }

    func scheduleSave() {
        guard
            isEnabled,
            model.customerContextLoaded,
            !isApplyingSnapshot
        else {
            return
        }

        model.customerContextSaveSucceeded = false
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak self] in
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
            saveDebounceTask?.cancel()
            saveDebounceTask = nil
            loadedKey = nil
            model.customerContextLoaded = false
            model.customerContextLoadFailed = false
            model.crmProfile = nil
        }
    }

    func saveNow(ignoringPreference: Bool = false) {
        guard
            (ignoringPreference || isEnabled),
            model.customerContextLoaded,
            !isApplyingSnapshot,
            let address = loadedAddress,
            let contextKey = loadedKey
        else {
            return
        }

        saveDebounceTask?.cancel()
        saveDebounceTask = nil

        let request = CustomerContextSaveRequest(
            address: address,
            displayName: loadedDisplayName,
            callIdentifier: callIdentifier,
            company: model.customerCompany,
            keys: listValues(model.customerKeys),
            emails: listValues(model.customerEmails),
            note: model.customerNote
        )
        saveGeneration += 1
        let generation = saveGeneration
        let previousSave = saveTail

        model.customerContextSaving = true
        model.customerContextSaveFailed = false
        model.customerContextSaveSucceeded = false

        let task = Task { [weak self] in
            if let previousSave {
                await previousSave.value
            }

            let result = await CustomerContextStore.shared.save(
                address: request.address,
                displayName: request.displayName,
                callIdentifier: request.callIdentifier,
                company: request.company,
                keys: request.keys,
                emails: request.emails,
                note: request.note
            )

            guard
                let self,
                self.loadedKey == contextKey,
                self.saveGeneration == generation
            else {
                return
            }

            self.model.customerContextSaving = false
            switch result {
            case .success:
                self.model.customerContextSaveFailed = false
                self.model.customerContextSaveSucceeded = true
            case .failure:
                self.model.customerContextSaveFailed = true
                self.model.customerContextSaveSucceeded = false
            }
        }
        saveTail = task
    }

    func retrySave() {
        saveNow()
    }

    func flushPendingChanges() async {
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        saveNow(ignoringPreference: true)

        if let saveTail {
            await saveTail.value
        }
    }

    func invalidate() {
        saveNow(ignoringPreference: true)

        loadTask?.cancel()
        loadTask = nil
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        loadedKey = nil
        loadedAddress = nil
        model.customerContextLoaded = false
    }

    private func resetPresentation() {
        model.customerCompany = ""
        model.customerKeys = ""
        model.customerEmails = ""
        model.customerNote = ""
        model.previousConversationCount = 0
        model.lastCallDate = nil
        model.recentCustomerNotes = []
        model.crmProfile = nil
        model.customerContextLoaded = false
        model.customerContextLoadFailed = false
        model.customerContextSaving = false
        model.customerContextSaveFailed = false
        model.customerContextSaveSucceeded = false
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


private struct CustomerContextSaveRequest: Sendable {
    let address: CustomerPartyAddress
    let displayName: String
    let callIdentifier: String
    let company: String
    let keys: [String]
    let emails: [String]
    let note: String
}
