//
//  CRMHistoryLookupModel.swift
//  Telephone
//

import Foundation
import Observation

enum CRMHistoryLocalError: Equatable {
    case loadFailed
    case invalidSavedSnapshot
    case saveFailed
    case recordRemoved
    case callerChanged
}

enum CRMHistoryPhoneLinkState: Equatable {
    case idle
    case refreshing
    case saving
    case saved(added: Bool)
    case failed(CRMGatewayError)
}

struct CRMHistoryPhoneLinkConfirmation: Equatable, Identifiable, Sendable {
    let id = UUID()
    let phone: String
    let companyID: Int
    let companyName: String
    let sourceKeyID: Int
    let expectedPhone: String
    let contextGeneration: Int
    let checkGeneration: Int
    let linkGeneration: Int
    let settingsGeneration: Int
}

@MainActor
@Observable
final class CRMHistoryLookupModel {
    let settings: CRMGatewaySettings
    private(set) var snapshot: CRMHistorySnapshot?
    private(set) var callerPhone: String?
    private(set) var isLoading = false
    private(set) var isChecking = false
    private(set) var isSaving = false
    private(set) var localError: CRMHistoryLocalError?
    private(set) var phoneLinkState: CRMHistoryPhoneLinkState = .idle
    private(set) var pendingPhoneLink: CRMHistoryPhoneLinkConfirmation?
    var keyNumber = "" {
        didSet { if oldValue != keyNumber { cancelCheck() } }
    }
    var email = "" {
        didSet { if oldValue != email { cancelCheck() } }
    }

    @ObservationIgnored private let storage: any CallHistoryCRMStorage
    @ObservationIgnored private let provider: any CRMKeyLookupProvider
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var context: HistoryContext?
    @ObservationIgnored private var contextGeneration = 0
    @ObservationIgnored private var checkGeneration = 0
    @ObservationIgnored private var settingsGeneration: Int
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var linkTask: Task<Void, Never>?
    @ObservationIgnored private var linkGeneration = 0
    @ObservationIgnored private var preparedKeySnapshot: CRMHistorySnapshot?

    init(
        storage: any CallHistoryCRMStorage,
        settings: CRMGatewaySettings,
        provider: any CRMKeyLookupProvider,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storage = storage
        self.settings = settings
        self.provider = provider
        self.now = now
        settingsGeneration = settings.generation
        observeSettings()
    }

    var canCheck: Bool {
        settings.enabled && context != nil && !isLoading && !isChecking && !isSaving
            && phoneLinkState != .refreshing && phoneLinkState != .saving
            && localError != .recordRemoved
    }

    var canLinkPhone: Bool {
        if case .saved = phoneLinkState { return false }
        guard canCheck, let phone = callerPhone, let snapshot,
              snapshot.status == .matched, case .key(let keyID) = snapshot.lookupIdentity,
              let customer = snapshot.customer, customer.sourceKeyId == keyID,
              CRMKeyNumber.parse(keyNumber) == keyID,
              CRMKeyNumber.isValid(keyID), customer.keys.contains(where: { $0.id == keyID }),
              !customer.company.containsPhone(phone), pendingPhoneLink == nil else { return false }
        return true
    }

    var isCallerLinkedToKey: Bool {
        guard let phone = callerPhone, let snapshot, snapshot.status == .matched,
              case .key = snapshot.lookupIdentity, let customer = snapshot.customer else { return false }
        return customer.company.containsPhone(phone)
    }

    var canSearchKey: Bool { canCheck && CRMKeyNumber.parse(keyNumber) != nil }
    var canSearchEmail: Bool { canCheck && CRMEmailAddress.normalize(email) != nil }

    func load(accountUUID: String, callIdentifier: String, checkNow: Bool = false) {
        close()
        let context = HistoryContext(accountUUID: accountUUID, callIdentifier: callIdentifier)
        self.context = context
        let generation = contextGeneration
        isLoading = true
        loadTask = Task { [weak self, storage] in
            do {
                let rawPhone = try await storage.phone(
                    accountUUID: context.accountUUID, callIdentifier: context.callIdentifier
                )
                guard let self, self.isCurrent(context, generation: generation) else { return }
                guard let rawPhone else {
                    self.localError = .recordRemoved
                    self.isLoading = false
                    return
                }
                self.callerPhone = CRMPhoneNumber.normalize(rawPhone)
                let stored = try await storage.load(
                    accountUUID: context.accountUUID, callIdentifier: context.callIdentifier
                )
                guard self.isCurrent(context, generation: generation) else { return }
                if let stored {
                    do {
                        let restored = try CRMHistorySnapshot.restored(from: stored)
                        guard restored.phone == self.callerPhone else {
                            throw CRMHistorySnapshotError.invalidSnapshot
                        }
                        self.snapshot = restored
                        switch restored.lookupIdentity {
                        case .key(let number): self.keyNumber = String(number)
                        case .email(let email): self.email = email
                        default: break
                        }
                    } catch {
                        self.localError = .invalidSavedSnapshot
                    }
                }
                self.isLoading = false
                self.loadTask = nil
                if checkNow { self.checkNow() }
            } catch {
                guard let self, self.isCurrent(context, generation: generation) else { return }
                self.isLoading = false
                self.loadTask = nil
                self.localError = .loadFailed
            }
        }
    }

    func checkNow() {
        let identity = snapshot?.lookupIdentity
        let companyID: Int?
        if case .key = identity { companyID = nil }
        else { companyID = snapshot?.customer?.company.id }
        performCheck(identity: identity, companyID: companyID)
    }

    func searchCallerPhone() {
        performCheck(identity: nil, companyID: nil)
    }

    func searchKey() {
        guard canSearchKey, let number = CRMKeyNumber.parse(keyNumber) else { return }
        performCheck(identity: .key(number), companyID: nil)
    }

    func searchEmail() {
        guard canSearchEmail, let email = CRMEmailAddress.normalize(email) else { return }
        performCheck(identity: .email(email), companyID: nil)
    }

    func chooseCompany(_ match: CRMPhoneLookupMatch) {
        guard canCheck, let snapshot, snapshot.status == .ambiguous,
              snapshot.matches.contains(where: { $0.id == match.id }) else { return }
        performCheck(identity: snapshot.lookupIdentity, companyID: match.id)
    }

    func cancelCheck() {
        invalidatePhoneLink()
        checkTask?.cancel()
        checkTask = nil
        checkGeneration &+= 1
        isChecking = false
        isSaving = false
    }

    func preparePhoneLink() {
        guard canLinkPhone, let context, let phone = callerPhone,
              let snapshot, case .key(let keyID) = snapshot.lookupIdentity,
              let originalCompanyID = snapshot.customer?.company.id else { return }
        invalidatePhoneLink()
        let contextGeneration = contextGeneration
        let checkGeneration = checkGeneration
        let linkGeneration = linkGeneration
        let settingsGeneration = settings.generation
        localError = nil
        phoneLinkState = .refreshing
        linkTask = Task { [weak self, storage, settings, provider, now] in
            do {
                guard let raw = try await storage.phone(
                    accountUUID: context.accountUUID, callIdentifier: context.callIdentifier
                ) else {
                    guard let self, self.isCurrentLink(context, contextGeneration, checkGeneration, linkGeneration, settingsGeneration) else { return }
                    self.phoneLinkState = .idle
                    self.localError = .recordRemoved
                    return
                }
                guard CRMPhoneNumber.normalize(raw) == phone else {
                    guard let self, self.isCurrentLink(context, contextGeneration, checkGeneration, linkGeneration, settingsGeneration) else { return }
                    self.phoneLinkState = .idle
                    self.localError = .callerChanged
                    return
                }
                let configuration = try await settings.configuration()
                try Task.checkCancellation()
                guard let self, self.isCurrentLink(context, contextGeneration, checkGeneration, linkGeneration, settingsGeneration) else { return }
                let response = try await provider.customer(forKeyNumber: keyID, configuration: configuration)
                try Task.checkCancellation()
                guard self.isCurrentLink(context, contextGeneration, checkGeneration, linkGeneration, settingsGeneration) else { return }
                let verified = try CRMHistorySnapshot.checkedKey(
                    response: response, keyNumber: keyID, phone: phone, checkedAt: now()
                )
                guard let company = verified.customer?.company,
                      company.id == originalCompanyID else {
                    throw CRMGatewayError.conflict
                }
                if company.containsPhone(phone) {
                    self.snapshot = verified
                    self.phoneLinkState = .saved(added: false)
                    self.isSaving = true
                    await self.saveLinkedSnapshot(
                        verified, context: context, contextGeneration: contextGeneration,
                        checkGeneration: checkGeneration, linkGeneration: linkGeneration,
                        settingsGeneration: settingsGeneration
                    )
                    return
                }
                guard let expectedPhone = response.data?.company.phone else {
                    throw CRMGatewayError.invalidResponse
                }
                self.preparedKeySnapshot = verified
                self.phoneLinkState = .idle
                self.linkTask = nil
                self.pendingPhoneLink = CRMHistoryPhoneLinkConfirmation(
                    phone: phone, companyID: company.id, companyName: company.name,
                    sourceKeyID: keyID, expectedPhone: expectedPhone,
                    contextGeneration: contextGeneration, checkGeneration: checkGeneration,
                    linkGeneration: linkGeneration, settingsGeneration: settingsGeneration
                )
            } catch {
                guard let self, self.isCurrentLink(context, contextGeneration, checkGeneration, linkGeneration, settingsGeneration) else { return }
                self.linkTask = nil
                self.phoneLinkState = error is CancellationError ? .idle
                    : .failed((error as? CRMGatewayError) ?? .unavailable)
            }
        }
    }

    func dismissPhoneLinkConfirmation() {
        guard pendingPhoneLink != nil else { return }
        invalidatePhoneLink()
    }

    func confirmPhoneLink(_ confirmation: CRMHistoryPhoneLinkConfirmation) {
        // SwiftUI may set the dialog binding to false after the confirmation
        // action has consumed it. A stale/repeated action must never cancel
        // the one write already in flight.
        guard pendingPhoneLink == confirmation else { return }
        guard let context,
              isCurrentLink(context, confirmation.contextGeneration, confirmation.checkGeneration,
                            confirmation.linkGeneration, confirmation.settingsGeneration),
              callerPhone == confirmation.phone,
              let prepared = preparedKeySnapshot, let preparedCustomer = prepared.customer,
              prepared.lookupIdentity == .key(confirmation.sourceKeyID),
              preparedCustomer.company.id == confirmation.companyID,
              !preparedCustomer.company.containsPhone(confirmation.phone) else {
            invalidatePhoneLink()
            return
        }
        pendingPhoneLink = nil
        preparedKeySnapshot = nil
        phoneLinkState = .saving
        linkTask = Task { [weak self, storage, settings, provider, now] in
            var appendDispatched = false
            do {
                let configuration = try await settings.configuration()
                try Task.checkCancellation()
                guard let raw = try await storage.phone(
                    accountUUID: context.accountUUID, callIdentifier: context.callIdentifier
                ) else {
                    guard let self, self.isCurrentLink(context, confirmation.contextGeneration, confirmation.checkGeneration,
                                                       confirmation.linkGeneration, confirmation.settingsGeneration) else { return }
                    self.phoneLinkState = .idle
                    self.linkTask = nil
                    self.localError = .recordRemoved
                    return
                }
                guard CRMPhoneNumber.normalize(raw) == confirmation.phone else {
                    guard let self, self.isCurrentLink(context, confirmation.contextGeneration, confirmation.checkGeneration,
                                                       confirmation.linkGeneration, confirmation.settingsGeneration) else { return }
                    self.phoneLinkState = .idle
                    self.linkTask = nil
                    self.localError = .callerChanged
                    return
                }
                try Task.checkCancellation()
                guard let self, self.isCurrentLink(context, confirmation.contextGeneration, confirmation.checkGeneration,
                                                   confirmation.linkGeneration, confirmation.settingsGeneration) else { return }
                appendDispatched = true
                let result = try await provider.appendPhone(
                    confirmation.phone, companyID: confirmation.companyID,
                    sourceKeyID: confirmation.sourceKeyID, expectedPhone: confirmation.expectedPhone,
                    configuration: configuration
                )
                guard self.isCurrentLink(context, confirmation.contextGeneration, confirmation.checkGeneration,
                                         confirmation.linkGeneration, confirmation.settingsGeneration) else { return }
                guard result.data.companyId == confirmation.companyID else {
                    throw CRMGatewayError.phoneWriteUnconfirmed
                }
                var phones = preparedCustomer.company.phones ?? []
                if let returned = result.data.phones {
                    phones = returned
                } else if !phones.contains(confirmation.phone) {
                    phones.append(confirmation.phone)
                }
                let company = preparedCustomer.company.replacingPhone(result.data.phone, phones: phones)
                let customer = CRMKeyLookupCustomer(
                    sourceKeyId: confirmation.sourceKeyID, company: company,
                    keys: preparedCustomer.keys
                )
                let checked: CRMHistorySnapshot
                do {
                    checked = try CRMHistorySnapshot.checkedKey(
                        response: CRMKeyLookupResponse(data: customer, meta: result.meta),
                        keyNumber: confirmation.sourceKeyID, phone: confirmation.phone, checkedAt: now()
                    )
                } catch {
                    self.phoneLinkState = .saved(added: result.data.added)
                    self.linkTask = nil
                    self.localError = .saveFailed
                    return
                }
                self.snapshot = checked
                self.phoneLinkState = .saved(added: result.data.added)
                self.isSaving = true
                await self.saveLinkedSnapshot(
                    checked, context: context,
                    contextGeneration: confirmation.contextGeneration,
                    checkGeneration: confirmation.checkGeneration,
                    linkGeneration: confirmation.linkGeneration,
                    settingsGeneration: confirmation.settingsGeneration
                )
            } catch {
                guard let self, self.isCurrentLink(context, confirmation.contextGeneration, confirmation.checkGeneration,
                                                   confirmation.linkGeneration, confirmation.settingsGeneration) else { return }
                self.linkTask = nil
                if !appendDispatched, !(error is CRMGatewayError) {
                    self.phoneLinkState = .idle
                    self.localError = .loadFailed
                    return
                }
                let typed = (error as? CRMGatewayError) ?? .phoneWriteUnconfirmed
                if appendDispatched {
                    switch typed {
                    case .forbidden, .unauthorized, .conflict, .rateLimited, .phoneWriteUnconfirmed:
                        self.phoneLinkState = .failed(typed)
                    default:
                        self.phoneLinkState = .failed(.phoneWriteUnconfirmed)
                    }
                } else {
                    self.phoneLinkState = .failed(typed)
                }
            }
        }
    }

    private func saveLinkedSnapshot(
        _ checked: CRMHistorySnapshot, context: HistoryContext,
        contextGeneration: Int, checkGeneration: Int, linkGeneration: Int, settingsGeneration: Int
    ) async {
        do {
            let stored = try checked.storedCheck()
            try Task.checkCancellation()
            guard isCurrentLink(context, contextGeneration, checkGeneration, linkGeneration, settingsGeneration) else { return }
            let saved = try await storage.save(
                stored, accountUUID: context.accountUUID, callIdentifier: context.callIdentifier
            )
            guard isCurrentLink(context, contextGeneration, checkGeneration, linkGeneration, settingsGeneration) else { return }
            isSaving = false
            linkTask = nil
            if !saved { localError = .recordRemoved }
        } catch {
            guard isCurrentLink(context, contextGeneration, checkGeneration, linkGeneration, settingsGeneration) else { return }
            isSaving = false
            linkTask = nil
            localError = .saveFailed
        }
    }

    private func invalidatePhoneLink() {
        let wasSaving = phoneLinkState == .saving
        linkTask?.cancel()
        linkTask = nil
        linkGeneration &+= 1
        pendingPhoneLink = nil
        preparedKeySnapshot = nil
        phoneLinkState = wasSaving ? .failed(.phoneWriteUnconfirmed) : .idle
    }

    private func isCurrentLink(
        _ context: HistoryContext, _ currentContextGeneration: Int,
        _ currentCheckGeneration: Int, _ currentLinkGeneration: Int, _ currentSettingsGeneration: Int
    ) -> Bool {
        isCurrent(context, generation: currentContextGeneration)
            && checkGeneration == currentCheckGeneration
            && linkGeneration == currentLinkGeneration
            && settings.generation == currentSettingsGeneration
    }

    func close() {
        contextGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
        cancelCheck()
        context = nil
        snapshot = nil
        callerPhone = nil
        keyNumber = ""
        email = ""
        localError = nil
        isLoading = false
    }

    private func performCheck(identity: CRMHistoryLookupIdentity?, companyID: Int?) {
        guard canCheck, let context else { return }
        cancelCheck()
        let contextGeneration = contextGeneration
        let checkGeneration = checkGeneration
        let settingsGeneration = settings.generation
        self.settingsGeneration = settingsGeneration
        localError = nil
        isChecking = true
        checkTask = Task { [weak self, storage, settings, provider, now] in
            let checked: CRMHistorySnapshot
            let phone: String?
            do {
                let raw = try await storage.phone(
                    accountUUID: context.accountUUID, callIdentifier: context.callIdentifier
                )
                guard let self, self.isCurrentCheck(
                    context, contextGeneration: contextGeneration,
                    checkGeneration: checkGeneration, settingsGeneration: settingsGeneration
                ) else { return }
                guard let raw else {
                    self.isChecking = false
                    self.localError = .recordRemoved
                    return
                }
                phone = CRMPhoneNumber.normalize(raw)
                self.callerPhone = phone
            } catch {
                guard let self, self.isCurrentCheck(
                    context, contextGeneration: contextGeneration,
                    checkGeneration: checkGeneration, settingsGeneration: settingsGeneration
                ) else { return }
                self.isChecking = false
                self.localError = .loadFailed
                return
            }

            let query = identity ?? phone.map(CRMHistoryLookupIdentity.phone)
            do {
                guard let query else { throw CRMGatewayError.invalidPhoneNumber }
                let configuration = try await settings.configuration()
                try Task.checkCancellation()
                guard settings.generation == settingsGeneration else { return }
                switch query {
                case .phone(let number):
                    let response = try await provider.customer(
                        forPhoneNumber: number, companyID: companyID, configuration: configuration
                    )
                    try Task.checkCancellation()
                    checked = try CRMHistorySnapshot.checked(
                        response: response, phone: number, checkedAt: now(), selectedCompanyID: companyID
                    )
                case .key(let number):
                    let response = try await provider.customer(forKeyNumber: number, configuration: configuration)
                    try Task.checkCancellation()
                    checked = try CRMHistorySnapshot.checkedKey(response: response, keyNumber: number, phone: phone, checkedAt: now())
                case .email(let email):
                    let response = try await provider.customer(forEmail: email, companyID: companyID, configuration: configuration)
                    try Task.checkCancellation()
                    checked = try CRMHistorySnapshot.checkedEmail(
                        response: response, email: email, phone: phone, checkedAt: now(), selectedCompanyID: companyID
                    )
                }
            } catch is CancellationError {
                guard let self, self.isCurrentCheck(
                    context, contextGeneration: contextGeneration,
                    checkGeneration: checkGeneration, settingsGeneration: settingsGeneration
                ) else { return }
                self.isChecking = false
                self.checkTask = nil
                return
            } catch {
                checked = CRMHistorySnapshot.failed(
                    phone: phone, error: (error as? CRMGatewayError) ?? .invalidResponse, checkedAt: now(), lookupIdentity: query
                )
            }
            guard let self, self.isCurrentCheck(
                context, contextGeneration: contextGeneration,
                checkGeneration: checkGeneration, settingsGeneration: settingsGeneration
            ) else { return }
            self.snapshot = checked
            self.isChecking = false
            self.isSaving = true
            do {
                let stored = try checked.storedCheck()
                try Task.checkCancellation()
                guard self.isCurrentCheck(
                    context, contextGeneration: contextGeneration,
                    checkGeneration: checkGeneration, settingsGeneration: settingsGeneration
                ) else { return }
                let saved = try await storage.save(
                    stored, accountUUID: context.accountUUID, callIdentifier: context.callIdentifier
                )
                guard self.isCurrentCheck(
                    context, contextGeneration: contextGeneration,
                    checkGeneration: checkGeneration, settingsGeneration: settingsGeneration
                ) else { return }
                self.isSaving = false
                self.checkTask = nil
                if !saved { self.localError = .recordRemoved }
            } catch {
                guard self.isCurrentCheck(
                    context, contextGeneration: contextGeneration,
                    checkGeneration: checkGeneration, settingsGeneration: settingsGeneration
                ) else { return }
                self.isSaving = false
                self.checkTask = nil
                self.localError = .saveFailed
            }
        }
    }

    private func isCurrent(_ context: HistoryContext, generation: Int) -> Bool {
        !Task.isCancelled && self.context == context && contextGeneration == generation
    }

    private func isCurrentCheck(
        _ context: HistoryContext,
        contextGeneration: Int,
        checkGeneration: Int,
        settingsGeneration: Int
    ) -> Bool {
        isCurrent(context, generation: contextGeneration)
            && self.checkGeneration == checkGeneration
            && settings.generation == settingsGeneration
    }

    private func observeSettings() {
        withObservationTracking { _ = settings.generation } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.settingsGeneration != self.settings.generation {
                    self.settingsGeneration = self.settings.generation
                    self.cancelCheck()
                }
                self.observeSettings()
            }
        }
    }
}

private struct HistoryContext: Equatable, Sendable {
    let accountUUID: String
    let callIdentifier: String
}
