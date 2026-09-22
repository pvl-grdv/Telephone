//
//  MusicPlayerCallEventTarget.swift
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

public final class MusicPlayerCallEventTarget {
    private let player: MusicPlayer

    public init(player: MusicPlayer) {
        self.player = player
    }
}

extension MusicPlayerCallEventTarget: CallEventTarget {
    public func didConnect(_ call: Call) {
        player.pause()
    }

    public func didDisconnect(_ call: Call) {
        player.resume()
    }

    public func didMake(_ call: Call) {}
    public func didReceive(_ call: Call) {}
    public func isConnecting(_ call: Call) {}
}
