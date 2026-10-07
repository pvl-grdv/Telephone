import Foundation
import Testing

struct CRMInventoryPresentationTests {
    @Test func ordersVersionsAndReleasesNumericallyAndRetainsHistory() {
        let records = [
            program(1, version: "4.9", release: "10"),
            program(2, version: "4.10", release: "0009"),
            program(3, version: "4.10", release: "0010"),
            program(4, version: "9.10"),
            program(5, version: "10.1"),
            program(6, version: nil, release: "9999"),
            program(7, version: "  "),
            program(8, version: "4.10", release: nil)
        ]
        let result = CRMInventoryPresentation(customer: customer(keys: [key(20, programs: records)]))
        #expect(result.keys[0].groups[0].records.map(\.recordId) == [5, 4, 3, 2, 8, 1, 6, 7])
        #expect(result.totalProgramGroupCount == 1)
        #expect(result.totalRecordCount == records.count)
        #expect(result.visibleRecordCount == records.count)
    }

    @Test func groupsByIdentityBeforeNameWithoutMergingDistinctPrograms() {
        let records = [
            program(1, programID: 100, name: "  Example  ", version: "1"),
            program(2, programID: 100, name: "Example renamed", version: "2"),
            program(3, programID: 101, name: "Example", version: "1"),
            program(4, programID: nil, name: " Example ", version: "1"),
            program(5, programID: nil, name: "EXAMPLE", version: "2"),
            program(6, programID: nil, name: "", version: "1"),
            program(7, programID: nil, name: "   ", version: "1")
        ]
        let result = CRMInventoryPresentation(customer: customer(keys: [key(20, programs: records)]))
        let groups = result.keys[0].groups
        #expect(groups.count == 5)
        #expect(groups.first(where: { $0.id == .program(100) })?.records.map(\.recordId) == [2, 1])
        #expect(groups.first(where: { $0.id == .program(100) })?.name == "Example renamed")
        #expect(groups.first(where: { $0.id == .program(101) })?.records.map(\.recordId) == [3])
        #expect(groups.first(where: { $0.id == .name("example") })?.records.map(\.recordId) == [5, 4])
        #expect(result.totalRecordCount == 7)
    }

    @Test func ordersSourceKeyFirstAndThenNumbersRatherThanLexicalText() {
        let result = CRMInventoryPresentation(customer: customer(
            sourceKeyID: 100, keys: [key(20), key(100), key(3), key(11)]
        ))
        #expect(result.keys.map(\.id) == [100, 3, 11, 20])
        #expect(result.keys.map(\.isSourceKey) == [true, false, false, false])
        #expect(result.visibleKeyCount == 4)
        #expect(result.visibleProgramGroupCount == 0)
        #expect(result.visibleRecordCount == 0)
    }

    @Test func groupsAreAlphabeticalAndOrderingDoesNotDependOnGatewayArrayOrder() {
        let records = [
            program(3, programID: 200, name: "Beta", version: "2"),
            program(2, programID: 100, name: "Alpha", version: "1", release: "0010"),
            program(1, programID: 100, name: "Alpha", version: "1", release: "0010")
        ]
        let original = CRMInventoryPresentation(customer: customer(keys: [key(20, programs: records)]))
        let reordered = CRMInventoryPresentation(customer: customer(keys: [key(20, programs: Array(records.reversed()))]))
        #expect(original.keys[0].groups == reordered.keys[0].groups)
        #expect(original.keys[0].groups.map(\.name) == ["Alpha", "Beta"])
        #expect(original.keys[0].groups[0].records.map(\.recordId) == [1, 2])
    }

    @Test func equivalentNumericVersionsUseReleaseThenNameThenRecordIdentity() {
        let result = CRMInventoryPresentation(customer: customer(keys: [key(20, programs: [
            program(8, name: "Zeta", version: "04.10", release: "0010"),
            program(5, name: "Alpha", version: "4.10", release: "10"),
            program(2, name: "Alpha", version: "4.10", release: "0010"),
            program(1, name: "Alpha", version: "4.10", release: "9"),
            program(9, name: "Alpha", version: "4.10", release: " ")
        ])]))
        #expect(result.keys[0].groups[0].records.map(\.recordId) == [2, 5, 8, 1, 9])
    }

    @Test func keySearchKeepsAllProgramsWhileProgramSearchKeepsMatchingGroupsHistory() {
        let inventory = customer(keys: [
            key(20, name: "Desktop", programs: [
                program(1, programID: 100, name: "Alpha", version: "4.9", release: "0007"),
                program(2, programID: 100, name: "Alpha", version: "4.10", release: "0008"),
                program(3, programID: 200, name: "Beta", version: "1")
            ]),
            key(30, name: "Backup")
        ])
        for query in ["20", " desktop "] {
            let result = CRMInventoryPresentation(customer: inventory, searchText: query)
            #expect(result.keys.map(\.id) == [20])
            #expect(result.visibleProgramGroupCount == 2)
            #expect(result.visibleRecordCount == 3)
        }
        for query in ["ALPHA", "4.10", "0007"] {
            let result = CRMInventoryPresentation(customer: inventory, searchText: query)
            #expect(result.keys.map(\.id) == [20])
            #expect(result.keys[0].groups.map(\.id) == [.program(100)])
            #expect(result.keys[0].groups[0].records.map(\.recordId) == [2, 1])
            #expect(result.totalKeyCount == 2)
            #expect(result.totalProgramGroupCount == 2)
            #expect(result.totalRecordCount == 3)
            #expect(result.visibleProgramGroupCount == 1)
            #expect(result.visibleRecordCount == 2)
            #expect(result.isFiltered)
        }
        let absent = CRMInventoryPresentation(customer: inventory, searchText: "missing")
        #expect(absent.keys.isEmpty)
        #expect(absent.totalRecordCount == 3)
        let unfiltered = CRMInventoryPresentation(customer: inventory, searchText: " \n ")
        #expect(!unfiltered.isFiltered)
        #expect(unfiltered.visibleKeyCount == 2)
    }

    @Test func searchMatchesNamesWithoutAccentAndGroupsRemainScopedToEachKey() {
        let result = CRMInventoryPresentation(customer: customer(keys: [
            key(20, programs: [program(1, name: "Éxample", version: "1")]),
            key(30, programs: [program(2, name: "Éxample", version: "2")])
        ]), searchText: "example")
        #expect(result.visibleKeyCount == 2)
        #expect(result.visibleProgramGroupCount == 2)
        #expect(result.visibleRecordCount == 2)
    }

    @Test func preparedInventoryCanBeFilteredRepeatedlyAndRestoredWithoutDroppingRecords() {
        let prepared = CRMInventoryPresentation(customer: customer(keys: [
            key(20, programs: [
                program(1, programID: 100, name: "Alpha", version: "4.9"),
                program(2, programID: 100, name: "Alpha", version: "4.10"),
                program(3, programID: 200, name: "Beta", version: "1")
            ]),
            key(30, name: "Backup")
        ]))
        let alpha = prepared.filtering("4.9")
        #expect(alpha.keys[0].groups[0].records.map(\.recordId) == [2, 1])
        // A new query starts from the complete prepared data, even if the
        // receiver was already filtered to a different program.
        let beta = alpha.filtering("Beta")
        #expect(beta.visibleRecordCount == 1)
        #expect(beta.keys[0].groups[0].records.map(\.recordId) == [3])
        #expect(beta.filtering("  ") == prepared)
        #expect(prepared.visibleRecordCount == 3)
    }

    @Test func measuresPreparingAndSearchingTenThousandSyntheticRecords() {
        let records = (1...100).map { recordID in
            let programID = (recordID - 1) / 4 + 1
            return program(recordID, programID: programID, name: "Program \(programID)",
                           version: String(100 - recordID), release: "0010")
        }
        let source = customer(sourceKeyID: 50, keys: (1...100).map { key($0, programs: records) })
        let clock = ContinuousClock()
        let started = clock.now
        let prepared = CRMInventoryPresentation(customer: source)
        let preparation = started.duration(to: clock.now)
        #expect(prepared.keys.first?.id == 50)
        #expect(prepared.totalRecordCount == 10_000)
        #expect(prepared.totalProgramGroupCount == 2_500)
        let searchStarted = clock.now
        for _ in 0..<30 {
            let filtered = prepared.filtering("Program 25")
            #expect(filtered.visibleKeyCount == 100)
            #expect(filtered.visibleRecordCount == 400)
            #expect(filtered.totalRecordCount == 10_000)
        }
        let searching = searchStarted.duration(to: clock.now)
        // Record timings without a hardware-dependent or flaky time limit.
        print("CRM inventory benchmark: 10,000 records; prepare=\(preparation); 30 searches=\(searching)")
    }

    private func customer(sourceKeyID: Int? = nil, keys: [CRMKeyLookupKey]) -> CRMKeyLookupCustomer {
        CRMKeyLookupCustomer(
            sourceKeyId: sourceKeyID,
            company: CRMKeyLookupCompany(id: 123, name: "Example Company", formattedCode: "00-00-0123", phone: nil, phones: nil),
            keys: keys
        )
    }

    private func key(_ id: Int, name: String = "Example key", programs: [CRMKeyLookupProgram] = []) -> CRMKeyLookupKey {
        CRMKeyLookupKey(id: id, name: name, url: URL(string: "https://example.test/keys/\(id)")!, programs: programs)
    }

    private func program(
        _ recordID: Int, programID: Int? = 100, name: String = "Example",
        version: String? = nil, release: String? = nil
    ) -> CRMKeyLookupProgram {
        CRMKeyLookupProgram(
            recordId: recordID, programId: programID, name: name, version: version, release: release,
            keyUrl: URL(string: "https://example.test/keys/20")!
        )
    }
}
