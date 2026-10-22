import Foundation

struct CRMProgramCatalogRecord: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let availableForSupply: Bool
    let signVersion: String?
    let signRelease: String?
    let signDirectory: String?
    let stealthVersion: String?
    let stealthRelease: String?
    let stealthDirectory: String?

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [String(id), name, signVersion, signRelease, signDirectory,
            stealthVersion, stealthRelease, stealthDirectory]
            .compactMap { $0 }.contains { $0.localizedStandardContains(query) }
    }
}

struct CRMProgramCatalogResponse: Decodable, Sendable {
    let data: [CRMProgramCatalogRecord]
    let meta: CRMKeyLookupMetadata
}

protocol CRMProgramCatalogProvider: Sendable {
    func programCatalog(configuration: CRMGatewayConfiguration) async throws -> CRMProgramCatalogResponse
}
