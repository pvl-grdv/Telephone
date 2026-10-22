import Foundation
import Observation

@MainActor @Observable
final class CRMProgramCatalogModel {
    let settings: CRMGatewaySettings
    var search = ""
    var availableOnly = true
    var usesStealth = false
    private(set) var records: [CRMProgramCatalogRecord] = []
    private(set) var isLoading = false
    private(set) var error: CRMGatewayError?
    private(set) var fetchedAt: String?
    @ObservationIgnored private let provider: any CRMProgramCatalogProvider
    @ObservationIgnored private var requestGeneration = 0

    init(settings: CRMGatewaySettings, provider: any CRMProgramCatalogProvider) {
        self.settings = settings
        self.provider = provider
    }

    var visibleRecords: [CRMProgramCatalogRecord] {
        records.filter { (!availableOnly || $0.availableForSupply) && $0.matches(search) }
            .sorted { lhs, rhs in
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
            }
    }

    func clear() {
        requestGeneration += 1
        records = []
        fetchedAt = nil
        error = nil
        isLoading = false
    }

    func reload() async {
        clear()
        let request = requestGeneration, settingsGeneration = settings.generation
        isLoading = true
        defer { if request == requestGeneration { isLoading = false } }
        do {
            let configuration = try await settings.configuration()
            let result = try await provider.programCatalog(configuration: configuration)
            try Task.checkCancellation()
            guard request == requestGeneration, settingsGeneration == settings.generation else { return }
            records = result.data
            fetchedAt = result.meta.fetchedAt
        } catch is CancellationError {
            return
        } catch {
            guard request == requestGeneration, settingsGeneration == settings.generation else { return }
            self.error = (error as? CRMGatewayError) ?? .unavailable
        }
    }
}
