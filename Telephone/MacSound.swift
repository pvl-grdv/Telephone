//
//  MacSound.swift
//  Telephone
//

import AppKit
import UseCases

final class MacSound: NSObject, Sound {
    private let sound: NSSound
    private let target: SoundEventTarget

    init(sound: NSSound, target: SoundEventTarget) {
        self.sound = sound
        self.target = target
        super.init()
        sound.delegate = self
    }

    deinit {
        if sound.delegate === self {
            sound.delegate = nil
        }
    }

    func play() {
        sound.play()
    }

    func stop() {
        sound.stop()
    }
}

extension MacSound: NSSoundDelegate {
    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        target.didFinishPlaying(self)
    }
}

final class MacSoundFactory {
    func makeSound(
        configuration: SoundConfiguration,
        target: SoundEventTarget
    ) throws -> Sound {
        guard let sound = NSSound(named: configuration.name) else {
            throw TelephoneError.soundCreationError
        }

        if !configuration.deviceUID.isEmpty {
            sound.playbackDeviceIdentifier = configuration.deviceUID
        }

        return MacSound(sound: sound, target: target)
    }
}
