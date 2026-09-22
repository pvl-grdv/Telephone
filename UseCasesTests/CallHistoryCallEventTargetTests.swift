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
