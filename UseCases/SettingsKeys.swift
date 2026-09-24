//
//  SettingsKeys.swift
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

public enum SettingsKeys {
    // Legacy display-name keys are retained for downgrade compatibility.
    public static let soundInput = "SoundInput"
    public static let soundOutput = "SoundOutput"
    public static let ringtoneOutput = "RingtoneOutput"

    // Stable CoreAudio identifiers used by current builds.
    public static let soundInputUID = "SoundInputUID"
    public static let soundOutputUID = "SoundOutputUID"
    public static let ringtoneOutputUID = "RingtoneOutputUID"
    public static let ringingSound = "RingingSound"

    // Keep the persisted key for compatibility with existing installs.
    public static let pauseMedia = "PauseITunes"
    public static let significantPhoneNumberLength = "SignificantPhoneNumberLength"
}
