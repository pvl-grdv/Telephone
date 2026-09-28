//
//  DelayedRestartSchedulerTests.swift
//  TelephoneTests
//

import XCTest

final class DelayedRestartSchedulerTests: XCTestCase {
    @MainActor
    func testDefersImmediatelyWhenCallIsAlreadyActive() async {
        var deferred = false
        var restarted = false
        let scheduler = DelayedRestartScheduler(delay: .milliseconds(10))

        scheduler.request(
            hasActiveCalls: { true },
            deferRestart: { deferred = true },
            restart: { restarted = true }
        )

        XCTAssertTrue(deferred)
        XCTAssertFalse(restarted)
    }

    @MainActor
    func testRechecksCallsAfterDelayBeforeRestarting() async {
        var callActive = false
        var deferred = false
        var restarted = false
        let deferredExpectation = expectation(description: "restart deferred")
        let (delayStream, delayContinuation) = AsyncStream<Void>.makeStream()
        let scheduler = DelayedRestartScheduler(
            delay: .seconds(3),
            sleep: { _ in
                for await _ in delayStream {
                    return
                }
            }
        )

        scheduler.request(
            hasActiveCalls: { callActive },
            deferRestart: {
                deferred = true
                deferredExpectation.fulfill()
            },
            restart: { restarted = true }
        )

        callActive = true
        delayContinuation.yield()

        await fulfillment(of: [deferredExpectation], timeout: 1)

        XCTAssertTrue(deferred)
        XCTAssertFalse(restarted)
    }

    @MainActor
    func testRestartsWhenNoCallAppearsDuringDelay() async {
        var deferred = false
        var restarted = false
        let restartExpectation = expectation(description: "restart performed")
        let (delayStream, delayContinuation) = AsyncStream<Void>.makeStream()
        let scheduler = DelayedRestartScheduler(
            delay: .seconds(3),
            sleep: { _ in
                for await _ in delayStream {
                    return
                }
            }
        )

        scheduler.request(
            hasActiveCalls: { false },
            deferRestart: { deferred = true },
            restart: {
                restarted = true
                restartExpectation.fulfill()
            }
        )

        delayContinuation.yield()

        await fulfillment(of: [restartExpectation], timeout: 1)

        XCTAssertFalse(deferred)
        XCTAssertTrue(restarted)
    }
}
