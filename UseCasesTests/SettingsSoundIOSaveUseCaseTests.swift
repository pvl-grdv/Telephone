//
//  SettingsSoundIOSaveUseCaseTests.swift
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

import Testing
import UseCases
import UseCasesTestDoubles

@MainActor
struct SettingsSoundIOSaveUseCaseTests {
    @Test func savesUIDsAndLegacyNamesForNormalDevices() {
        let settings = SettingsFake()
        let sut = SettingsSoundIOSaveUseCase(
            soundIO: SystemDefaultingSoundIO(
                input: .device(
                    uniqueIdentifier: "input-uid",
                    name: "Input"
                ),
                output: .device(
                    uniqueIdentifier: "output-uid",
                    name: "Output"
                ),
                ringtoneOutput: .device(
                    uniqueIdentifier: "ringtone-uid",
                    name: "Ringtone"
                )
            ),
            settings: settings
        )

        sut.execute()

        #expect(settings[SettingsKeys.soundInputUID] == "input-uid")
        #expect(settings[SettingsKeys.soundOutputUID] == "output-uid")
        #expect(
            settings[SettingsKeys.ringtoneOutputUID] == "ringtone-uid"
        )
        #expect(settings[SettingsKeys.soundInput] == "Input")
        #expect(settings[SettingsKeys.soundOutput] == "Output")
        #expect(settings[SettingsKeys.ringtoneOutput] == "Ringtone")
    }

    @Test func clearsUIDsAndNamesForSystemDefaults() {
        let settings = SettingsFake()
        for key in [
            SettingsKeys.soundInputUID,
            SettingsKeys.soundOutputUID,
            SettingsKeys.ringtoneOutputUID,
            SettingsKeys.soundInput,
            SettingsKeys.soundOutput,
            SettingsKeys.ringtoneOutput,
        ] {
            settings[key] = "any-value"
        }

        let sut = SettingsSoundIOSaveUseCase(
            soundIO: SystemDefaultingSoundIO(
                input: .systemDefault,
                output: .systemDefault,
                ringtoneOutput: .systemDefault
            ),
            settings: settings
        )

        sut.execute()

        #expect(settings[SettingsKeys.soundInputUID] == nil)
        #expect(settings[SettingsKeys.soundOutputUID] == nil)
        #expect(settings[SettingsKeys.ringtoneOutputUID] == nil)
        #expect(settings[SettingsKeys.soundInput] == nil)
        #expect(settings[SettingsKeys.soundOutput] == nil)
        #expect(settings[SettingsKeys.ringtoneOutput] == nil)
    }
}
