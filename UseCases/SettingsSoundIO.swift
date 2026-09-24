//
//  SettingsSoundIO.swift
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

@MainActor
struct SettingsSoundIO {
    private let devices: SystemAudioDevices
    private let settings: KeyValueSettings
    private var optionalInput: SystemAudioDevice!
    private var optionalOutput: SystemAudioDevice!
    private var optionalRingtoneOutput: SystemAudioDevice!

    init(devices: SystemAudioDevices, settings: KeyValueSettings) {
        self.devices = devices
        self.settings = settings

        optionalInput = device(
            uniqueIdentifierKey: SettingsKeys.soundInputUID,
            legacyNameKey: SettingsKeys.soundInput,
            byUniqueIdentifier: {
                devices.inputDevice(uniqueIdentifier: $0)
            },
            byName: {
                devices.inputDevice(named: $0)
            }
        )
        optionalOutput = device(
            uniqueIdentifierKey: SettingsKeys.soundOutputUID,
            legacyNameKey: SettingsKeys.soundOutput,
            byUniqueIdentifier: {
                devices.outputDevice(uniqueIdentifier: $0)
            },
            byName: {
                devices.outputDevice(named: $0)
            }
        )
        optionalRingtoneOutput = device(
            uniqueIdentifierKey: SettingsKeys.ringtoneOutputUID,
            legacyNameKey: SettingsKeys.ringtoneOutput,
            byUniqueIdentifier: {
                devices.outputDevice(uniqueIdentifier: $0)
            },
            byName: {
                devices.outputDevice(named: $0)
            }
        )
    }

    private func device(
        uniqueIdentifierKey: String,
        legacyNameKey: String,
        byUniqueIdentifier: (String) -> SystemAudioDevice,
        byName: (String) -> SystemAudioDevice
    ) -> SystemAudioDevice {
        if let uniqueIdentifier = settings.string(
            forKey: uniqueIdentifierKey
        ) {
            let device = byUniqueIdentifier(uniqueIdentifier)
            if !device.isNil {
                return device
            }
        }

        guard let name = settings.string(forKey: legacyNameKey) else {
            return NullSystemAudioDevice()
        }

        let device = byName(name)
        if !device.isNil {
            settings[uniqueIdentifierKey] = device.uniqueIdentifier
        }
        return device
    }
}

extension SettingsSoundIO: SoundIO {
    var input: SystemAudioDevice {
        optionalInput
    }

    var output: SystemAudioDevice {
        optionalOutput
    }

    var ringtoneOutput: SystemAudioDevice {
        optionalRingtoneOutput
    }
}
