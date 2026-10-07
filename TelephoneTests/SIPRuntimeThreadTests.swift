import Foundation
import Synchronization
import Testing

@Suite(.serialized)
struct SIPRuntimeThreadTests {
    private final class Results: Sendable {
        let values = Mutex<[Int]>([])
        func append(_ value: Int) { values.withLock { $0.append(value) } }
        var snapshot: [Int] { values.withLock { $0 } }
    }

    @Test func shutdownDrainsAcceptedWorkInOrderAndRejectsNewWork() {
        let worker = SIPRuntimeThread()
        let results = Results()
        for value in 0..<100 {
            #expect(worker.perform { results.append(value) })
        }
        worker.shutdown()
        #expect(results.snapshot == Array(0..<100))
        #expect(!worker.perform { results.append(100) })
        #expect(results.snapshot.count == 100)
        worker.shutdown()
    }

    @Test func synchronousWorkAfterShutdownReturnsWithoutWaiting() {
        let worker = SIPRuntimeThread()
        worker.shutdown()
        let results = Results()
        let done = DispatchSemaphore(value: 0)
        // Use a dedicated caller: blocking a Swift Testing executor while
        // waiting for its shared GCD pool can starve the work under test.
        let caller = Thread {
            let accepted = worker.performAndWait { results.append(1) }
            results.append(accepted ? 2 : 3)
            done.signal()
        }
        caller.qualityOfService = .userInitiated
        caller.start()
        // Bounds a regression without hanging the entire test process.
        #expect(done.wait(timeout: .now() + 2) == .success)
        #expect(results.snapshot == [3])
    }

    @Test func nestedSynchronousWorkRunsOnTheSameRuntimeThread() {
        let worker = SIPRuntimeThread()
        defer { worker.shutdown() }
        let results = Results()
        let done = DispatchSemaphore(value: 0)
        #expect(worker.perform {
            results.append(1)
            let accepted = worker.performAndWait { results.append(2) }
            results.append(accepted ? 3 : 4)
            done.signal()
        })
        #expect(done.wait(timeout: .now() + 2) == .success)
        #expect(results.snapshot == [1, 2, 3])
    }

    @Test func shutdownOnRuntimeThreadRejectsNestedNewWorkWithoutDeadlock() {
        let worker = SIPRuntimeThread()
        let results = Results()
        let done = DispatchSemaphore(value: 0)
        #expect(worker.perform {
            worker.shutdown()
            let accepted = worker.performAndWait { results.append(1) }
            results.append(accepted ? 2 : 3)
            done.signal()
        })
        #expect(done.wait(timeout: .now() + 2) == .success)
        worker.shutdown()
        #expect(results.snapshot == [3])
    }

    @Test func concurrentShutdownCallersBothWaitForAcceptedWorkToFinish() throws {
        let worker = SIPRuntimeThread()
        let results = Results()
        let operationStarted = DispatchSemaphore(value: 0)
        let releaseOperation = DispatchSemaphore(value: 0)
        let callersStarted = DispatchSemaphore(value: 0)
        let callerReturned = DispatchSemaphore(value: 0)
        let allReturned = DispatchGroup()
        defer { releaseOperation.signal(); worker.shutdown() }
        #expect(worker.perform {
            operationStarted.signal()
            releaseOperation.wait()
            results.append(1)
        })
        try #require(operationStarted.wait(timeout: .now() + 2) == .success)
        for _ in 0..<2 {
            allReturned.enter()
            let caller = Thread {
                callersStarted.signal()
                worker.shutdown()
                results.append(results.snapshot.first == 1 ? 2 : 0)
                callerReturned.signal()
                allReturned.leave()
            }
            caller.qualityOfService = .userInitiated
            caller.start()
        }
        try #require(callersStarted.wait(timeout: .now() + 2) == .success)
        try #require(callersStarted.wait(timeout: .now() + 2) == .success)
        // While the accepted operation is blocked, neither join may return.
        #expect(callerReturned.wait(timeout: .now() + .milliseconds(50)) == .timedOut)
        releaseOperation.signal()
        #expect(allReturned.wait(timeout: .now() + 2) == .success)
        #expect(results.snapshot == [1, 2, 2])
    }

    @Test func workerDoesNotRetainItsOwnerWhileIdle() {
        weak var reference: SIPRuntimeThread?
        autoreleasepool {
            let worker = SIPRuntimeThread()
            reference = worker
            #expect(worker.performAndWait {})
        }
        #expect(reference == nil)
    }
}
