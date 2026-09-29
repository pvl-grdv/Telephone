//
//  CRMKeyLookupModel.swift
//  Telephone
//

import Foundation
import Observation

enum CRMKeyLookupState: Equatable {
    case idle
    case loading
    case notFound
    case loaded(CRMKeyLookupResponse)
    case failed(CRMGatewayError)
}

@MainActor
@Observable
final class CRMKeyLookupModel {
    let settings: CRMGatewaySettings
    var keyNumber = "" {
        didSet { if oldValue != keyNumber { cancel() } }
    }
    private(set) var state: CRMKeyLookupState = .idle

    @ObservationIgnored private let provider: any CRMKeyLookupProvider
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var contextGeneration = 0
    @ObservationIgnored private var requestGeneration = 0
    @ObservationIgnored private var presentedSettingsGeneration: Int

    init(settings: CRMGatewaySettings, provider: any CRMKeyLookupProvider) {
        self.settings = settings
        self.provider = provider
        presentedSettingsGeneration = settings.generation
        observeSettings()
    }

    var canSearch: Bool {
        settings.enabled && CRMKeyNumber.parse(keyNumber) != nil && state != .loading
    }

    func search() {
        task?.cancel()
        requestGeneration &+= 1
        let requestGeneration = requestGeneration
        let contextGeneration = contextGeneration
        let settingsGeneration = settings.generation
        presentedSettingsGeneration = settingsGeneration
        guard let number = CRMKeyNumber.parse(keyNumber) else {
            state = .failed(.invalidKeyNumber)
            return
        }
        state = .loading
        task = Task { [weak self, settings, provider] in
            do {
                let configuration = try await settings.configuration()
                try Task.checkCancellation()
                guard settings.generation == settingsGeneration else { return }
                let result = try await provider.customer(
                    forKeyNumber: number,
                    configuration: configuration
                )
                guard let self, self.isCurrent(
                    request: requestGeneration,
                    context: contextGeneration,
                    settings: settingsGeneration
                ) else { return }
                self.state = result.data == nil ? .notFound : .loaded(result)
                self.task = nil
            } catch {
                guard let self, self.isCurrent(
                    request: requestGeneration,
                    context: contextGeneration,
                    settings: settingsGeneration
                ) else { return }
                self.task = nil
                if error is CancellationError {
                    self.state = .idle
                } else {
                    self.state = .failed((error as? CRMGatewayError) ?? .unavailable)
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        requestGeneration &+= 1
        state = .idle
    }

    func resetContext() {
        contextGeneration &+= 1
        cancel()
        keyNumber = ""
    }

    func settingsDidChange() {
        guard settings.generation != presentedSettingsGeneration else { return }
        presentedSettingsGeneration = settings.generation
        cancel()
    }

    private func isCurrent(request: Int, context: Int, settings: Int) -> Bool {
        !Task.isCancelled
            && requestGeneration == request
            && contextGeneration == context
            && self.settings.generation == settings
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.generation
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.settingsDidChange()
                self?.observeSettings()
            }
        }
    }
}
