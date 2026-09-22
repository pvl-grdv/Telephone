//
//  AvailableMusicPlayers.swift
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

final class AvailableMusicPlayers: MusicPlayer {
    private let players: [MusicPlayer]

    init(factory: MusicPlayerFactory) {
        players = [
            factory.makeMusicAppMusicPlayer(),
            factory.makeSpotifyMusicPlayer()
        ].compactMap { $0 }
    }

    func pause() {
        players.forEach { $0.pause() }
    }

    func resume() {
        players.forEach { $0.resume() }
    }
}
