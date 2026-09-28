//
//  WorkspaceSleepStatusTests.swift
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
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

import Foundation
import XCTest

final class WorkspaceSleepStatusTests: XCTestCase {
    private let willSleep = Notification.Name("WorkspaceWillSleep")
    private let didWake = Notification.Name("WorkspaceDidWake")

    func testIsNotSleepingAfterCreation() {
        let fixture = makeFixture()

        XCTAssertFalse(fixture.sut.isSleeping)
    }

    func testIsSleepingAfterWillSleepNotification() {
        let fixture = makeFixture()

        fixture.center.post(
            name: willSleep,
            object: fixture.workspace
        )

        XCTAssertTrue(fixture.sut.isSleeping)
    }

    func testIsNotSleepingAfterDidWakeNotification() {
        let fixture = makeFixture()

        fixture.center.post(
            name: willSleep,
            object: fixture.workspace
        )
        fixture.center.post(
            name: didWake,
            object: fixture.workspace
        )

        XCTAssertFalse(fixture.sut.isSleeping)
    }

    private func makeFixture() -> (
        sut: WorkspaceSleepStatus,
        center: NotificationCenter,
        workspace: NSObject
    ) {
        let center = NotificationCenter()
        let workspace = NSObject()
        return (
            WorkspaceSleepStatus(
                center: center,
                willSleepNotification: willSleep,
                didWakeNotification: didWake,
                workspace: workspace
            ),
            center,
            workspace
        )
    }
}
