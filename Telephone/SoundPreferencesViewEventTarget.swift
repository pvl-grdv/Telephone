//
//  SoundPreferencesViewEventTarget.swift
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
import UseCases

@MainActor
final class SoundPreferencesViewEventTarget {
    private let useCaseFactory: UseCaseFactory
    private let userAgentSoundIOSelection: UseCase
    private let ringtoneOutputUpdate: ThrowingUseCase
    private let ringtoneSoundPlayback: SoundPlaybackUseCase

    init(useCaseFactory: UseCaseFactory,
         userAgentSoundIOSelection: UseCase,
         ringtoneOutputUpdate: ThrowingUseCase,
         ringtoneSoundPlayback: SoundPlaybackUseCase) {
        self.useCaseFactory = useCaseFactory
        self.userAgentSoundIOSelection = userAgentSoundIOSelection
        self.ringtoneOutputUpdate = ringtoneOutputUpdate
        self.ringtoneSoundPlayback = ringtoneSoundPlayback
    }

    func reloadSoundIO(in view: SoundPreferencesView) {
        do {
            try useCaseFactory.makeSettingsSoundIOLoadUseCase(
                output: SoundIOPresenter(output: view)
            ).execute()
        } catch {
            let nsError = error as NSError
            Log.audio.error(
                """
                Could not load Sound IO view data \
                domain=\(nsError.domain, privacy: .public) \
                code=\(nsError.code, privacy: .public) \
                description=\(nsError.localizedDescription, privacy: .private)
                """
            )
        }
    }

    func didChangeSoundIO(_ soundIO: PresentationSoundIO) {
        useCaseFactory.makeSettingsSoundIOSaveUseCase(
            soundIO: SystemDefaultingSoundIO(soundIO)
        ).execute()
        userAgentSoundIOSelection.execute()
        updateRingtoneOutputOrLogError()
    }

    func didChangeRingtoneName(_ name: String) {
        useCaseFactory.makeSettingsRingtoneSoundNameSaveUseCase(name: name).execute()
        playRingtoneSoundOrLogError()
    }

    func stopRingtonePreview() {
        ringtoneSoundPlayback.stop()
    }
}

private extension SoundPreferencesViewEventTarget {
    func updateRingtoneOutputOrLogError() {
        do {
            try ringtoneOutputUpdate.execute()
        } catch {
            let nsError = error as NSError
            Log.audio.error(
                """
                Could not update ringtone output \
                domain=\(nsError.domain, privacy: .public) \
                code=\(nsError.code, privacy: .public) \
                description=\(nsError.localizedDescription, privacy: .private)
                """
            )
        }
    }

    func playRingtoneSoundOrLogError() {
        do {
            try ringtoneSoundPlayback.play()
        } catch {
            let nsError = error as NSError
            Log.audio.error(
                """
                Could not play ringtone sound \
                domain=\(nsError.domain, privacy: .public) \
                code=\(nsError.code, privacy: .public) \
                description=\(nsError.localizedDescription, privacy: .private)
                """
            )
        }
    }

}
