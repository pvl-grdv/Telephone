//
//  UserAgentStartUseCaseTests.swift
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
final class UserAgentStartUseCaseTests: XCTestCase {
    func testSetsFullCallLimitAndStartsUserAgent() {
        let didCallStart = expectation(description: "Calls start on agent")
        let agent = UserAgentSpy(startCallback: didCallStart.fulfill)
        let sut = UserAgentStartUseCase(agent: agent)

        sut.execute()

        wait(for: [didCallStart], timeout: 1)
        XCTAssertEqual(agent.maxCalls, 30)
    }
}
