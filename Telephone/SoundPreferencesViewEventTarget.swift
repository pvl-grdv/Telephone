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
    private let presenterFactory: PresenterFactory
    private let userAgentSoundIOSelection: UseCase
    private let ringtoneOutputUpdate: ThrowingUseCase
    private let ringtoneSoundPlayback: SoundPlaybackUseCase

    init(useCaseFactory: UseCaseFactory,
         presenterFactory: PresenterFactory,
         userAgentSoundIOSelection: UseCase,
         ringtoneOutputUpdate: ThrowingUseCase,
         ringtoneSoundPlayback: SoundPlaybackUseCase) {
        self.useCaseFactory = useCaseFactory
        self.presenterFactory = presenterFactory
        self.userAgentSoundIOSelection = userAgentSoundIOSelection
        self.ringtoneOutputUpdate = ringtoneOutputUpdate
        self.ringtoneSoundPlayback = ringtoneSoundPlayback
    }

    func shouldReloadData(in view: SoundPreferencesView) {
        loadSettingsSoundIOInViewOrLogError(view: view)
    }

    func shouldReloadSoundIO(in view: SoundPreferencesView) {
        loadSettingsSoundIOInViewOrLogError(view: view)
    }

    func didChangeSoundIO(_ soundIO: PresentationSoundIO) {
        updateSettings(withSoundIO: soundIO)
        userAgentSoundIOSelection.execute()
        updateRingtoneOutputOrLogError()
    }

    func didChangeRingtoneName(_ name: String) {
        updateSettings(withRingtoneSoundName: name)
        playRingtoneSoundOrLogError()
    }

    func willDisappear(_ view: SoundPreferencesView) {
        ringtoneSoundPlayback.stop()
    }
}

private extension SoundPreferencesViewEventTarget {
    func loadSettingsSoundIOInViewOrLogError(view: SoundPreferencesView) {
        do {
            try makeSettingsSoundIOLoadUseCase(view: view).execute()
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

    func updateSettings(withSoundIO soundIO: PresentationSoundIO) {
        useCaseFactory.makeSettingsSoundIOSaveUseCase(soundIO: SystemDefaultingSoundIO(soundIO)).execute()
    }

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

    func updateSettings(withRingtoneSoundName name: String) {
        useCaseFactory.makeSettingsRingtoneSoundNameSaveUseCase(name: name).execute()
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

    func makeSettingsSoundIOLoadUseCase(view: SoundPreferencesView) -> ThrowingUseCase {
        return useCaseFactory.makeSettingsSoundIOLoadUseCase(
            output: presenterFactory.makeSoundIOPresenter(output: view)
        )
    }
}
