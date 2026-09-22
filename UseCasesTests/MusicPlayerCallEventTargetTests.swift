//
//  MusicPlayerCallEventTargetTests.swift
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

final class MusicPlayerCallEventTargetTests: XCTestCase {
    func testDoesNotPauseBeforeCallConnects() {
        let player = MusicPlayerSpy()
        let sut = makeSUT(player: player)

        sut.didMake(CallTestFactory().make())
        sut.didReceive(CallTestFactory().make())
        sut.isConnecting(CallTestFactory().make())

        XCTAssertFalse(player.didCallPause)
    }

    func testPausesConnectedCallWhenEnabled() {
        let player = MusicPlayerSpy()
        let sut = makeSUT(player: player, shouldPause: true)

        sut.didConnect(CallTestFactory().make())

        XCTAssertTrue(player.didCallPause)
    }

    func testDoesNotPauseConnectedCallWhenDisabled() {
        let player = MusicPlayerSpy()
        let sut = makeSUT(player: player, shouldPause: false)

        sut.didConnect(CallTestFactory().make())

        XCTAssertFalse(player.didCallPause)
    }

    func testResumesAfterLastCallDisconnectsWhenEnabled() {
        let player = MusicPlayerSpy()
        let sut = makeSUT(player: player, haveActiveCalls: false, shouldPause: true)

        sut.didDisconnect(CallTestFactory().make())

        XCTAssertTrue(player.didCallResume)
    }

    func testDoesNotResumeWhileAnotherCallIsActive() {
        let player = MusicPlayerSpy()
        let sut = makeSUT(player: player, haveActiveCalls: true, shouldPause: true)

        sut.didDisconnect(CallTestFactory().make())

        XCTAssertFalse(player.didCallResume)
    }

    func testDoesNotResumeWhenMediaPauseIsDisabled() {
        let player = MusicPlayerSpy()
        let sut = makeSUT(player: player, haveActiveCalls: false, shouldPause: false)

        sut.didDisconnect(CallTestFactory().make())

        XCTAssertFalse(player.didCallResume)
    }

    private func makeSUT(
        player: MusicPlayer = MusicPlayerSpy(),
        haveActiveCalls: Bool = false,
        shouldPause: Bool = true
    ) -> MusicPlayerCallEventTarget {
        let settings = MusicPlayerSettingsFake()
        settings.shouldPause = shouldPause
        return MusicPlayerCallEventTarget(
            player: player,
            calls: CallsStub(haveActive: haveActiveCalls),
            settings: settings
        )
    }
}
