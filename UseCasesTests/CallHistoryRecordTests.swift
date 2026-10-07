//
//  CallHistoryRecordTests.swift
//  UseCasesTests
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

import UseCases
import XCTest

final class CallHistoryRecordTests: XCTestCase {
    func testIdentifierContainsUserHostDateDurationIncomingFlag() {
        let user = "any-user"
        let host = "any-host"
        let date = Date()
        let duration = 10

        let sut = CallHistoryRecord(
            uri: URI(user: user, host: host, displayName: ""),
            date: date,
            duration: duration,
            isIncoming: true,
            isMissed: false
        )

        XCTAssertEqual(
            sut.identifier,
            "\(user)@\(host)|\(date.timeIntervalSinceReferenceDate)|\(duration)|\(sut.isIncoming ? 1 : 0)"
        )
    }
    func testRemovingHostPreservesExplicitCallIdentity() {
        let record = CallHistoryRecord(uri: URI(user: "+70005550101", host: "account.invalid", displayName: ""),
            date: Date(timeIntervalSinceReferenceDate: 10), duration: 12,
            isIncoming: true, isMissed: false, identifier: "stable-conversation")
        XCTAssertEqual(record.removingHost().identifier, "stable-conversation")
        XCTAssertEqual(record.removingHost().uri.host, "")
    }

    func testRemovingHostPreservesLegacyStoredIdentity() {
        let record = CallHistoryRecord(uri: URI(user: "101", host: "account.invalid", displayName: ""),
            date: Date(timeIntervalSinceReferenceDate: 10), duration: 0,
            isIncoming: true, isMissed: true)
        XCTAssertEqual(record.removingHost().identifier, record.identifier)
    }

    func testIdenticalCallDetailsDoNotCollapseDistinctConversationIdentities() {
        let uri = URI(user: "101", host: "account.invalid", displayName: "")
        let date = Date(timeIntervalSinceReferenceDate: 10)
        let first = CallHistoryRecord(uri: uri, date: date, duration: 0,
            isIncoming: true, isMissed: true, identifier: "first")
        let second = CallHistoryRecord(uri: uri, date: date, duration: 0,
            isIncoming: true, isMissed: true, identifier: "second")
        XCTAssertNotEqual(first, second)
    }

}
