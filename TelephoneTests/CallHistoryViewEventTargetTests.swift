//
//  CallHistoryViewEventTargetTests.swift
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

@MainActor
final class CallHistoryViewEventTargetTests: XCTestCase {
    func testReloadExecutesRecordsGet() {
        let recordsGet = UseCaseSpy()
        let sut = makeSUT(recordsGet: recordsGet)

        sut.shouldReloadData()

        XCTAssertTrue(recordsGet.didCallExecute)
    }

    func testHistoryUpdateExecutesRecordsGet() {
        let didExecute = expectation(description: "Reloads updated history")
        let sut = makeSUT(recordsGet: UseCaseSpy(callBack: didExecute.fulfill))

        sut.didUpdate(TruncatingCallHistory())

        wait(for: [didExecute], timeout: 1)
    }

    func testDayChangeExecutesRecordsGet() {
        let didExecute = expectation(description: "Reloads history for new day")
        let sut = makeSUT(recordsGet: UseCaseSpy(callBack: didExecute.fulfill))

        sut.dayDidChange()

        wait(for: [didExecute], timeout: 1)
    }

    func testRemoveAllExecutesUseCase() {
        let removeAll = UseCaseSpy()
        let sut = makeSUT(recordRemoveAll: removeAll)

        sut.shouldRemoveAllRecords()

        XCTAssertTrue(removeAll.didCallExecute)
    }

    func testPickRecordPassesIdentifierToCallAction() {
        var invokedIdentifier: String?
        let sut = makeSUT(makeCall: { invokedIdentifier = $0 })

        sut.didPickRecord(withIdentifier: "record-id")

        XCTAssertEqual(invokedIdentifier, "record-id")
    }

    func testRemoveRecordPassesIdentifierToRemoveAction() {
        var invokedIdentifier: String?
        let sut = makeSUT(removeRecord: { invokedIdentifier = $0 })

        sut.shouldRemoveRecord(withIdentifier: "record-id")

        XCTAssertEqual(invokedIdentifier, "record-id")
    }

    private func makeSUT(
        recordsGet: UseCase = UseCaseSpy(),
        recordRemoveAll: UseCase = UseCaseSpy(),
        removeRecord: @escaping (String) -> Void = { _ in },
        makeCall: @escaping (String) -> Void = { _ in }
    ) -> CallHistoryViewEventTarget {
        CallHistoryViewEventTarget(
            recordsGet: recordsGet,
            recordRemoveAll: recordRemoveAll,
            removeRecord: removeRecord,
            makeCall: makeCall
        )
    }
}
