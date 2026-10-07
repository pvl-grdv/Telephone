//
//  CRMKeyLookupModel.swift
//  Telephone
//

import Foundation
import Observation

enum CRMKeyLookupState: Equatable, Sendable {
    case idle
    case loading
    case notFound
    case choosing([CRMPhoneLookupMatch])
    case loaded(CRMKeyLookupResponse)
    case failed(CRMGatewayError)
}

struct CRMPhoneLinkConfirmation: Equatable, Identifiable, Sendable {
    let id = UUID()
    let phone: String
    let companyID: Int
    let companyName: String
    let sourceKeyID: Int
    let expectedPhone: String
    let appendRevision: Int
    let contextGeneration: Int
    let requestGeneration: Int
    let settingsGeneration: Int
}

@MainActor
@Observable
final class CRMKeyLookupModel {
    let settings: CRMGatewaySettings
    var keyNumber = "" {
        didSet { if oldValue != keyNumber { cancel() } }
    }
    var email = "" {
        didSet { if oldValue != email { cancel() } }
    }
    private(set) var callerPhone: String?
    private(set) var state: CRMKeyLookupState = .idle
    private var appendOperation = CRMPhoneAppendOperation()
    @ObservationIgnored private let appendRegistry: CRMPhoneAppendRegistry
    @ObservationIgnored private var appendAttemptID: UUID?
    private(set) var phoneLinkState: CRMPhoneLinkState {
        get { appendOperation.state }
        set { appendOperation.state = newValue }
    }
    var pendingPhoneLink: CRMPhoneLinkConfirmation?

    @ObservationIgnored private let provider: any CRMKeyLookupProvider
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var linkTask: Task<Void, Never>?
    @ObservationIgnored private var contextGeneration = 0
    @ObservationIgnored private var requestGeneration = 0
    @ObservationIgnored private var presentedSettingsGeneration: Int
    @ObservationIgnored private var isContextActive = true
    @ObservationIgnored private var automaticLookupAttempted = false
    @ObservationIgnored private var loadedFromKey = false
    @ObservationIgnored private var lookupIdentity: LiveCRMQuery?

    init(
        settings: CRMGatewaySettings, provider: any CRMKeyLookupProvider,
        appendRegistry: CRMPhoneAppendRegistry = CRMPhoneAppendRegistry()
    ) {
        self.settings = settings
        self.provider = provider
        self.appendRegistry = appendRegistry
        presentedSettingsGeneration = settings.generation
        observeSettings()
    }

    var canSearch: Bool {
        settings.enabled && isContextActive && CRMKeyNumber.parse(keyNumber) != nil
            && state != .loading && phoneLinkState != .saving
    }

    var canSearchEmail: Bool {
        settings.enabled && isContextActive && CRMEmailAddress.normalize(email) != nil
            && state != .loading && phoneLinkState != .saving
    }

    var canLinkPhone: Bool {
        if case .saved = phoneLinkState { return false }
        if case .failed = phoneLinkState { return false }
        guard !appendOperation.hasPendingRequest, settings.enabled, isContextActive, loadedFromKey,
              presentedSettingsGeneration == settings.generation,
              let phone = callerPhone, case .loaded(let response) = state,
              let customer = response.data, customer.sourceKeyId != nil,
              customer.company.phone != nil else { return false }
        return phoneLinkState != .saving
            && !customer.company.containsPhone(phone)
    }

    var isCallerAlreadyLinked: Bool {
        guard let phone = callerPhone, case .loaded(let response) = state,
              let customer = response.data else { return false }
        if case .saved = phoneLinkState { return true }
        if case .phone = lookupIdentity { return true }
        return customer.company.containsPhone(phone)
    }

    func setCallerPhone(_ raw: String?, isActive: Bool) {
        let phone = raw.flatMap(CRMPhoneNumber.normalize)
        if callerPhone != phone {
            resetContext()
            callerPhone = phone
        }
        isContextActive = isActive
        if isActive { startAutomaticLookupIfNeeded() } else { cancel() }
    }

    func activateContext() {
        isContextActive = true
        startAutomaticLookupIfNeeded()
    }

    func deactivateContext() {
        isContextActive = false
        cancel()
        automaticLookupAttempted = false
    }

    func search() {
        guard isContextActive, phoneLinkState != .saving else { return }
        guard let number = CRMKeyNumber.parse(keyNumber) else {
            state = .failed(.invalidKeyNumber)
            return
        }
        beginLookup { provider, configuration in
            let result = try await provider.customer(forKeyNumber: number, configuration: configuration)
            return result.data == nil ? .notFound : .loaded(result)
        }
        lookupIdentity = .key(number)
        loadedFromKey = true
    }

    func searchEmail(companyID: Int? = nil) {
        guard settings.enabled, isContextActive, phoneLinkState != .saving else { return }
        guard let email = CRMEmailAddress.normalize(email) else {
            cancel()
            state = .failed(.invalidEmail)
            return
        }
        loadedFromKey = false
        lookupIdentity = .email(email)
        beginLookup { provider, configuration in
            let result = try await provider.customer(forEmail: email, companyID: companyID, configuration: configuration)
            if result.data != nil { return .loaded(CRMKeyLookupResponse(data: result.data, meta: result.meta)) }
            return result.matches.isEmpty ? .notFound : .choosing(result.matches)
        }
    }

    func searchCallerPhone(companyID: Int? = nil) {
        guard settings.enabled, isContextActive, phoneLinkState != .saving,
              let phone = callerPhone else { return }
        automaticLookupAttempted = true
        loadedFromKey = false
        lookupIdentity = .phone(phone)
        beginLookup { provider, configuration in
            let result = try await provider.customer(
                forPhoneNumber: phone, companyID: companyID, configuration: configuration
            )
            if result.data != nil {
                return .loaded(CRMKeyLookupResponse(data: result.data, meta: result.meta))
            }
            return result.matches.isEmpty ? .notFound : .choosing(result.matches)
        }
    }

    func chooseCompany(_ match: CRMPhoneLookupMatch) {
        guard case .choosing(let matches) = state,
              matches.contains(where: { $0.id == match.id }) else { return }
        switch lookupIdentity {
        case .phone: searchCallerPhone(companyID: match.id)
        case .email: searchEmail(companyID: match.id)
        default: break
        }
    }

    func preparePhoneLink() {
        guard canLinkPhone, let phone = callerPhone,
              case .loaded(let response) = state, let customer = response.data,
              let keyID = customer.sourceKeyId,
              let expectedPhone = customer.company.phone else { return }
        pendingPhoneLink = CRMPhoneLinkConfirmation(
            phone: phone, companyID: customer.company.id, companyName: customer.company.name,
            sourceKeyID: keyID, expectedPhone: expectedPhone,
            appendRevision: appendOperation.revision,
            contextGeneration: contextGeneration, requestGeneration: requestGeneration,
            settingsGeneration: settings.generation
        )
    }

    func confirmPhoneLink(_ confirmation: CRMPhoneLinkConfirmation) {
        guard pendingPhoneLink == confirmation, canLinkPhone,
              appendOperation.revision == confirmation.appendRevision,
              callerPhone == confirmation.phone,
              contextGeneration == confirmation.contextGeneration,
              requestGeneration == confirmation.requestGeneration,
              settings.generation == confirmation.settingsGeneration,
              case .loaded(let original) = state, let customer = original.data else {
            pendingPhoneLink = nil
            return
        }
        pendingPhoneLink = nil
        guard let attempt = appendOperation.begin() else { return }
        appendAttemptID = attempt
        linkTask = Task { [weak self, settings, provider, appendOperation] in
            defer { appendOperation.abandonBeforeDispatch(attempt) }
            do {
                let configuration = try await settings.configuration()
                try Task.checkCancellation()
                guard let self, self.isCurrent(
                    request: confirmation.requestGeneration, context: confirmation.contextGeneration,
                    settings: confirmation.settingsGeneration
                ), appendOperation.dispatch(attempt) else { return }
                let result = try await provider.appendPhone(
                    confirmation.phone, companyID: confirmation.companyID,
                    sourceKeyID: confirmation.sourceKeyID, expectedPhone: confirmation.expectedPhone,
                    configuration: configuration
                )
                guard result.data.companyId == confirmation.companyID else {
                    throw CRMGatewayError.phoneWriteUnconfirmed
                }
                appendOperation.finish(attempt, added: result.data.added)
                guard self.isCurrent(
                    request: confirmation.requestGeneration,
                    context: confirmation.contextGeneration,
                    settings: confirmation.settingsGeneration
                ) else { return }
                self.state = .loaded(CRMKeyLookupResponse(
                    data: CRMKeyLookupCustomer(
                        sourceKeyId: customer.sourceKeyId,
                        company: customer.company.replacingPhone(result.data.phone, phones: result.data.phones), keys: customer.keys
                    ),
                    meta: result.meta
                ))
                self.linkTask = nil
                self.appendAttemptID = nil
            } catch {
                appendOperation.fail(attempt, error: error)
                guard let self, self.isCurrent(
                    request: confirmation.requestGeneration,
                    context: confirmation.contextGeneration,
                    settings: confirmation.settingsGeneration
                ) else { return }
                self.linkTask = nil
                self.appendAttemptID = nil
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        linkTask?.cancel()
        linkTask = nil
        requestGeneration &+= 1
        pendingPhoneLink = nil
        appendOperation.cancelPresentation(for: appendAttemptID)
        appendAttemptID = nil
        state = .idle
        loadedFromKey = false
        lookupIdentity = nil
    }

    func resetContext() {
        contextGeneration &+= 1
        cancel()
        keyNumber = ""
        email = ""
        callerPhone = nil
        appendOperation = CRMPhoneAppendOperation()
        automaticLookupAttempted = false
    }

    func settingsDidChange() {
        guard settings.generation != presentedSettingsGeneration else { return }
        presentedSettingsGeneration = settings.generation
        cancel()
        automaticLookupAttempted = false
        startAutomaticLookupIfNeeded()
    }

    private func startAutomaticLookupIfNeeded() {
        guard !automaticLookupAttempted, callerPhone != nil,
              isContextActive, settings.enabled else { return }
        searchCallerPhone()
    }

    private func beginLookup(
        _ operation: @escaping @Sendable (any CRMKeyLookupProvider, CRMGatewayConfiguration) async throws -> CRMKeyLookupState
    ) {
        task?.cancel()
        requestGeneration &+= 1
        let requestGeneration = requestGeneration
        let contextGeneration = contextGeneration
        let settingsGeneration = settings.generation
        presentedSettingsGeneration = settingsGeneration
        pendingPhoneLink = nil
        state = .loading
        let appendReceipt = appendRegistry.readReceipt()
        task = Task { [weak self, settings, provider] in
            do {
                let configuration = try await settings.configuration()
                try Task.checkCancellation()
                guard settings.generation == settingsGeneration else { return }
                let result = try await operation(provider, configuration)
                guard let self, self.isCurrent(
                    request: requestGeneration, context: contextGeneration, settings: settingsGeneration
                ) else { return }
                if case .loaded(let response) = result, let customer = response.data, let phone = self.callerPhone {
                    self.appendOperation = self.appendRegistry.operation(
                        origin: settings.origin, phone: phone, companyID: customer.company.id
                    )
                    self.appendRegistry.acceptFreshRead(
                        origin: settings.origin, phone: phone, companyID: customer.company.id, receipt: appendReceipt
                    )
                }
                self.state = result
                self.task = nil
            } catch {
                guard let self, self.isCurrent(
                    request: requestGeneration, context: contextGeneration, settings: settingsGeneration
                ) else { return }
                self.task = nil
                self.state = error is CancellationError ? .idle
                    : .failed((error as? CRMGatewayError) ?? .unavailable)
            }
        }
    }

    private func isCurrent(request: Int, context: Int, settings: Int) -> Bool {
        !Task.isCancelled && isContextActive && requestGeneration == request
            && contextGeneration == context && self.settings.generation == settings
    }

    private func observeSettings() {
        withObservationTracking { _ = settings.generation } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.settingsDidChange()
                self?.observeSettings()
            }
        }
    }
}

private enum LiveCRMQuery: Sendable {
    case phone(String)
    case key(Int)
    case email(String)
}
