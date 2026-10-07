import Foundation
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CallDestinationContactIndexTests {
    @Test func overlappingReadersShareALoadAndThenUseTheCache() async {
        let loader = SuspendedContactLoader()
        let index = CallDestinationContactIndex(loader: { await loader.load() })
        let expected = [record("current")]
        let first = Task { await index.records() }
        await loader.waitForStart(1)
        let second = Task { await index.records() }
        await loader.finish(1, with: expected)

        #expect(await first.value == expected)
        #expect(await second.value == expected)
        #expect(await index.records() == expected)
        #expect(await loader.startedCount == 1)
    }

    @Test func invalidationDuringALoadMakesTheWaitingCallerReload() async {
        let loader = SuspendedContactLoader()
        let index = CallDestinationContactIndex(loader: { await loader.load() })
        let reader = Task { await index.records() }
        await loader.waitForStart(1)
        await index.invalidate()
        // This loader deliberately finishes despite cancellation, as an
        // enumeration already executing in Contacts may do.
        await loader.finish(1, with: [record("obsolete")])
        await loader.waitForStart(2)
        let expected = [record("fresh")]
        await loader.finish(2, with: expected)

        #expect(await reader.value == expected)
        #expect(await index.records() == expected)
        #expect(await loader.cancelledLoads == [1])
        #expect(await loader.startedCount == 2)
    }

    @Test func newerForcedRefreshWinsEvenWhenTheOldLoadFinishesFirst() async {
        let loader = SuspendedContactLoader()
        let index = CallDestinationContactIndex(loader: { await loader.load() })
        let originalReader = Task { await index.records() }
        await loader.waitForStart(1)
        let refresh = Task { await index.records(forceReload: true) }
        await loader.waitForStart(2)
        await loader.finish(1, with: [record("obsolete")])
        let expected = [record("fresh")]
        await loader.finish(2, with: expected)

        #expect(await refresh.value == expected)
        #expect(await originalReader.value == expected)
        #expect(await index.records() == expected)
        #expect(await loader.startedCount == 2)
    }

    @Test func lateOldResultCannotOverwriteAnAlreadyCompletedRefresh() async {
        let loader = SuspendedContactLoader()
        let index = CallDestinationContactIndex(loader: { await loader.load() })
        let originalReader = Task { await index.records() }
        await loader.waitForStart(1)
        let refresh = Task { await index.records(forceReload: true) }
        await loader.waitForStart(2)
        let expected = [record("fresh")]
        await loader.finish(2, with: expected)
        #expect(await refresh.value == expected)
        await loader.finish(1, with: [record("obsolete")])

        #expect(await originalReader.value == expected)
        #expect(await index.records() == expected)
        #expect(await loader.startedCount == 2)
    }

    @Test func cancellingAReaderDoesNotCancelTheSharedLoad() async {
        let loader = SuspendedContactLoader()
        let index = CallDestinationContactIndex(loader: { await loader.load() })
        let cancelledReader = Task { await index.records() }
        await loader.waitForStart(1)
        let otherReader = Task { await index.records() }
        cancelledReader.cancel()
        let expected = [record("fresh")]
        await loader.finish(1, with: expected)

        #expect(await cancelledReader.value.isEmpty)
        #expect(await otherReader.value == expected)
        #expect(await index.records() == expected)
        #expect(await loader.cancelledLoads.isEmpty)
        #expect(await loader.startedCount == 1)
    }

    @Test func emptyRecordsAreCachedUntilInvalidation() async {
        let loader = SuspendedContactLoader()
        let index = CallDestinationContactIndex(loader: { await loader.load() })
        let first = Task { await index.records() }
        await loader.waitForStart(1)
        await loader.finish(1, with: [])
        #expect(await first.value.isEmpty)
        #expect(await index.records().isEmpty)
        #expect(await loader.startedCount == 1)

        await index.invalidate()
        let second = Task { await index.records() }
        await loader.waitForStart(2)
        let expected = [record("new-contact")]
        await loader.finish(2, with: expected)
        #expect(await second.value == expected)
        #expect(await loader.startedCount == 2)
    }

    private func record(_ id: String) -> CallDestinationContactRecord {
        CallDestinationContactRecord(
            id: id,
            displayName: id,
            organizationName: "",
            givenName: id,
            familyName: "",
            destinations: [.init(value: "+70005550101", label: "", kind: .phone)]
        )
    }
}

// Controlled continuations establish the exact interleaving without sleeps,
// access to Contacts, or relying on scheduler timing. A cancelled loader may
// still produce records, so generation checks are exercised independently.
private actor SuspendedContactLoader {
    private(set) var startedCount = 0
    private(set) var cancelledLoads: [Int] = []
    private var results: [Int: CheckedContinuation<[CallDestinationContactRecord], Never>] = [:]
    private var startWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var isAborted = false

    func load() async -> [CallDestinationContactRecord] {
        guard !isAborted else { return [] }
        startedCount += 1
        let id = startedCount
        let records: [CallDestinationContactRecord] = await withCheckedContinuation { continuation in
            results[id] = continuation
            for waiter in startWaiters.removeValue(forKey: id) ?? [] {
                waiter.resume()
            }
        }
        if Task.isCancelled {
            cancelledLoads.append(id)
        }
        return records
    }

    func waitForStart(_ id: Int) async {
        guard startedCount < id, !isAborted else { return }
        if Task.isCancelled { abortWaits(); return }
        // A failed generation regression must also exit when the suite's
        // time limit cancels the test. Index invalidation still deliberately
        // does not cancel the fake loader's continuation.
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                startWaiters[id, default: []].append(continuation)
            }
        } onCancel: {
            Task { await self.abortWaits() }
        }
    }

    func finish(_ id: Int, with records: [CallDestinationContactRecord]) {
        guard let continuation = results.removeValue(forKey: id) else {
            Issue.record("Contact load \(id) was not pending")
            return
        }
        continuation.resume(returning: records)
    }

    private func abortWaits() {
        isAborted = true
        let pendingResults = Array(results.values)
        results.removeAll()
        let pendingStarts = startWaiters.values.flatMap { $0 }
        startWaiters.removeAll()
        for continuation in pendingResults { continuation.resume(returning: []) }
        for continuation in pendingStarts { continuation.resume() }
    }
}
