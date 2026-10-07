//
//  CRMInventoryPresentation.swift
//  Telephone
//

import Foundation

/// Display ordering and filtering of the gateway inventory. It does not infer
/// whether a version is licensed or active: every gateway record is retained.
struct CRMInventoryPresentation: Equatable, Sendable {
    struct Key: Equatable, Identifiable, Sendable {
        let key: CRMKeyLookupKey
        let isSourceKey: Bool
        let groups: [ProgramGroup]
        var id: Int { key.id }
        var recordCount: Int { groups.reduce(0) { $0 + $1.records.count } }
    }

    struct ProgramGroup: Equatable, Identifiable, Sendable {
        enum ID: Hashable, Sendable {
            case program(Int)
            case name(String)
            case record(Int)
        }

        let id: ID
        let name: String
        let records: [CRMKeyLookupProgram]
        var recordCount: Int { records.count }
    }

    let keys: [Key]
    let totalKeyCount: Int
    let totalProgramGroupCount: Int
    let totalRecordCount: Int
    let isFiltered: Bool

    var visibleKeyCount: Int { keys.count }
    var visibleProgramGroupCount: Int { keys.reduce(0) { $0 + $1.groups.count } }
    var visibleRecordCount: Int { keys.reduce(0) { $0 + $1.recordCount } }

    init(customer: CRMKeyLookupCustomer, searchText: String = "") {
        let allKeys = customer.keys.map { key in
            Key(key: key, isSourceKey: key.id == customer.sourceKeyId, groups: Self.groups(for: key.programs))
        }.sorted {
            if $0.isSourceKey != $1.isSourceKey { return $0.isSourceKey }
            if $0.id != $1.id { return $0.id < $1.id }
            return Self.compare($0.key.name, $1.key.name) == .orderedAscending
        }
        totalKeyCount = allKeys.count
        totalProgramGroupCount = allKeys.reduce(0) { $0 + $1.groups.count }
        totalRecordCount = allKeys.reduce(0) { $0 + $1.recordCount }

        let query = Self.trim(searchText)
        isFiltered = !query.isEmpty
        if query.isEmpty {
            keys = allKeys
        } else {
            keys = allKeys.compactMap { item in
                if Self.matches(String(item.id), query: query) || Self.matches(item.key.name, query: query) {
                    return item
                }
                // Keep the full version history of each matching program group.
                let groups = item.groups.filter { group in
                    group.records.contains { record in
                        [record.name, record.version ?? "", record.release ?? ""].contains {
                            Self.matches($0, query: query)
                        }
                    }
                }
                guard !groups.isEmpty else { return nil }
                return Key(key: item.key, isSourceKey: item.isSourceKey, groups: groups)
            }
        }
    }

    private static let comparisonLocale = Locale(identifier: "en_US_POSIX")

    private static func groups(for programs: [CRMKeyLookupProgram]) -> [ProgramGroup] {
        let recordsByGroup = Dictionary(grouping: programs) { program -> ProgramGroup.ID in
            if let programID = program.programId { return .program(programID) }
            let name = trim(program.name)
            if name.isEmpty { return .record(program.recordId) }
            return .name(name.folding(options: [.caseInsensitive], locale: comparisonLocale))
        }
        return recordsByGroup.map { id, programs in
            let records = programs.sorted(by: recordPrecedes)
            return ProgramGroup(id: id, name: trim(records[0].name), records: records)
        }.sorted {
            let order = compare($0.name, $1.name)
            if order != .orderedSame { return order == .orderedAscending }
            return groupIdentity($0.id) < groupIdentity($1.id)
        }
    }

    private static func recordPrecedes(_ lhs: CRMKeyLookupProgram, _ rhs: CRMKeyLookupProgram) -> Bool {
        let versionOrder = descendingOptionalOrder(lhs.version, rhs.version)
        if versionOrder != .orderedSame { return versionOrder == .orderedAscending }
        let releaseOrder = descendingOptionalOrder(lhs.release, rhs.release)
        if releaseOrder != .orderedSame { return releaseOrder == .orderedAscending }
        let nameOrder = compare(trim(lhs.name), trim(rhs.name))
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.recordId < rhs.recordId
    }

    /// Numeric text ordering also handles releases with leading zeroes and
    /// non-semantic version labels. Missing or blank values follow known values.
    private static func descendingOptionalOrder(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        let left = trim(lhs ?? "")
        let right = trim(rhs ?? "")
        if left.isEmpty != right.isEmpty { return left.isEmpty ? .orderedDescending : .orderedAscending }
        let order = compare(left, right)
        switch order {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: [.numeric, .caseInsensitive], locale: comparisonLocale)
    }

    private static func matches(_ value: String, query: String) -> Bool {
        value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: comparisonLocale) != nil
    }

    private static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func groupIdentity(_ id: ProgramGroup.ID) -> String {
        switch id {
        case .program(let value): return "program:\(value)"
        case .name(let value): return "name:\(value)"
        case .record(let value): return "record:\(value)"
        }
    }
}
