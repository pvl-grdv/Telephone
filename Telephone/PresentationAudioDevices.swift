//
//  PresentationAudioDevices.swift
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

import Domain
import Foundation

final class PresentationAudioDevices: Hashable {
    let input: [PresentationAudioDevice]
    let output: [PresentationAudioDevice]
    var ringtoneOutput: [PresentationAudioDevice] { output }

    init(input: [PresentationAudioDevice], output: [PresentationAudioDevice]) {
        self.input = input
        self.output = output
    }
}

extension PresentationAudioDevices {
    static func == (
        lhs: PresentationAudioDevices,
        rhs: PresentationAudioDevices
    ) -> Bool {
        lhs.input == rhs.input && lhs.output == rhs.output
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(input)
        hasher.combine(output)
    }
}
