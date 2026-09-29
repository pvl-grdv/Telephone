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
            && localError != .recordRemoved
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
        checkTask?.cancel()
        checkTask = nil
        checkGeneration &+= 1
        isChecking = false
        isSaving = false
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
