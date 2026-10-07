//
//  CallHistoryCallEventTargetTests.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import UseCases
import UseCasesTestDoubles
import XCTest

final class CallHistoryCallEventTargetTests: XCTestCase {
    func testAddsDisconnectedCallToExpectedAccountHistory() async {
        let didAdd = expectation(description: "Adds disconnected call")
        let history = CallHistorySpy(
            addCallback: didAdd.fulfill,
            removeCallback: {},
            removeAllCallback: {}
        )
        let factory = CallHistoryFactorySpy(history: history)
        let histories = DefaultCallHistories(factory: factory)
        let sut = CallHistoryCallEventTarget(histories: histories)
        let account = SimpleAccount(uuid: "account-id", domain: "account.example")
        let call = makeCall(account: account)

        sut.didDisconnect(call)

        await fulfillment(of: [didAdd], timeout: 1)
        XCTAssertEqual(factory.invokedUUID, account.uuid)
        let records = await history.allRecords
        XCTAssertEqual(records, [CallHistoryRecord(call: call)])
    }
    func testDrainWaitsForAllWritesInEventOrder() async {
        let history = CallHistorySpy(addCallback: {}, removeCallback: {}, removeAllCallback: {})
        let factory = CallHistoryFactorySpy(history: history)
        let sut = CallHistoryCallEventTarget(histories: DefaultCallHistories(factory: factory))
        let account = SimpleAccount(uuid: "account-id", domain: "account.invalid")
        let calls = (0..<20).map { i in
            SimpleCall(account: account, remote: URI(user: "user-\(i)", host: "remote.invalid", displayName: ""),
                date: Date(timeIntervalSinceReferenceDate: Double(i)), duration: i,
                isIncoming: false, isMissed: false)
        }
        for call in calls { sut.didDisconnect(call) }
        await sut.drain()
        let records = await history.allRecords
        XCTAssertEqual(records.map { $0.uri.user }, calls.map { $0.remote.user })
        await sut.drain()
        let secondRead = await history.allRecords
        XCTAssertEqual(secondRead.count, 20)
    }

    func testDisconnectSnapshotsCallAndAccountBeforeSuspension() async {
        let history = CallHistorySpy(addCallback: {}, removeCallback: {}, removeAllCallback: {})
        let factory = CallHistoryFactorySpy(history: history)
        let sut = CallHistoryCallEventTarget(histories: DefaultCallHistories(factory: factory))
        let call = MutableHistoryCall()
        sut.didDisconnect(call)
        call.duration = 999
        call.remote = URI(user: "changed", host: "changed.invalid", displayName: "")
        call.account = SimpleAccount(uuid: "other-account", domain: "other.invalid")
        await sut.drain()
        let records = await history.allRecords
        XCTAssertEqual(factory.invokedUUID, "original-account")
        XCTAssertEqual(records.first?.duration, 12)
        XCTAssertEqual(records.first?.uri.user, "original")
        XCTAssertEqual(records.first?.identifier, "stable-call")
        XCTAssertEqual(records.first?.uri.host, "")
    }

}

private func makeCall(account: Account) -> Call {
    SimpleCall(
        account: account,
        remote: URI(user: "any-user", host: "remote.example", displayName: "any-name"),
        date: Date(),
        duration: 60,
        isIncoming: false,
        isMissed: false
    )
}


private final class MutableHistoryCall: NSObject, Call, CallHistoryIdentified, @unchecked Sendable {
    let historyIdentifier = "stable-call"
    var account: Account = SimpleAccount(uuid: "original-account", domain: "original.invalid")
    var remote = URI(user: "original", host: "original.invalid", displayName: "")
    let date = Date(timeIntervalSinceReferenceDate: 10)
    var duration = 12
    let isIncoming = true
    let isMissed = false
}
