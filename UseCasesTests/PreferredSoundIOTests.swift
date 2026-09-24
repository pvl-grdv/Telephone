//
//  PreferredSoundIOTests.swift
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
import DomainTestDoubles
import Testing
@testable import UseCases
import UseCasesTestDoubles

@MainActor
struct PreferredSoundIOTests {
    private let factory = SystemAudioDeviceTestFactory()
    private let settings = SettingsFake()

    // MARK: - Sound input

    @Test func inputIsDeviceWithUIDFromSettings() {
        let someDevice = factory.someInput
        settings[SettingsKeys.soundInputUID] = someDevice.uniqueIdentifier

        let sut = makeSoundIO()

        #expect(sut.input == someDevice)
    }

    @Test func inputUIDDisambiguatesDevicesWithSameName() {
        let first = SimpleSystemAudioDevice(
            identifier: 101,
            uniqueIdentifier: "same-name-1",
            name: "USB Audio",
            inputs: 1,
            outputs: 0,
            isBuiltIn: false
        )
        let second = SimpleSystemAudioDevice(
            identifier: 102,
            uniqueIdentifier: "same-name-2",
            name: "USB Audio",
            inputs: 1,
            outputs: 0,
            isBuiltIn: false
        )
        settings[SettingsKeys.soundInputUID] = second.uniqueIdentifier

        let sut = makeSoundIO(devices: [first, second])

        #expect(sut.input.uniqueIdentifier == second.uniqueIdentifier)
    }

    @Test func legacyInputNameMigratesToUID() {
        let someDevice = factory.someInput
        settings[SettingsKeys.soundInput] = someDevice.name

        let sut = makeSoundIO()

        #expect(sut.input == someDevice)
        #expect(
            settings[SettingsKeys.soundInputUID]
                == someDevice.uniqueIdentifier
        )
    }

    @Test func inputIsDefaultInputWhenThereIsNoSoundInputInSettings() {
        let defaultIO = SimpleSystemSoundIO(input: factory.someInput, output: NullSystemAudioDevice())

        let sut = makeSoundIO(devices: factory.all, settings: settings, defaultIO: defaultIO)

        #expect(sut.input == defaultIO.input)
    }

    @Test func inputIsDefaultInputWhenSoundInputUIDFromSettingsCanNotBeFoundInSystemDevices() {
        settings[SettingsKeys.soundInputUID] = nonexistentDeviceUID
        let defaultIO = SimpleSystemSoundIO(input: factory.someInput, output: NullSystemAudioDevice())

        let sut = makeSoundIO(devices: factory.all, settings: settings, defaultIO: defaultIO)

        #expect(sut.input == defaultIO.input)
    }

    @Test func inputIsBuiltInInputWhenThereIsNoSoundInputInSettingsAndThereIsNoDefaultInput() {
        let sut = makeSoundIO()

        #expect(sut.input == factory.firstBuiltInInput)
    }

    @Test func inputIsBuiltInInputWhenSoundInputUIDFromSettingsCanNotBeFoundInSystemDevicesAndThereIsNoDefaultInput() {
        settings[SettingsKeys.soundInputUID] = nonexistentDeviceUID

        let sut = makeSoundIO()

        #expect(sut.input == factory.firstBuiltInInput)
    }

    @Test func inputIsBuiltInInputWhenAudioDeviceMatchedByUIDFromSettingsDoesNotHaveInputChannelsAndThereIsNoDefaultInput() {
        settings[SettingsKeys.soundInputUID] = factory.outputOnly.uniqueIdentifier

        let sut = makeSoundIO()

        #expect(sut.input == factory.firstBuiltInInput)
    }

    @Test func inputIsFirstInputWhenNotFoundInSettingsAndThereIsNoDefaultInputAndThereIsNoBuiltInInput() {
        let sut = makeSoundIO(devices: [factory.firstInput, factory.someInput, factory.someOutput])

        #expect(sut.input == factory.firstInput)
    }

    // MARK: - Sound output

    @Test func outputIsDeviceWithUIDFromSettings() {
        let someDevice = factory.someOutput
        settings[SettingsKeys.soundOutputUID] = someDevice.uniqueIdentifier

        let sut = makeSoundIO()

        #expect(sut.output == someDevice)
    }

    @Test func outputIsDefaultOutputWhenThereIsNoSoundOutputInSettings() {
        let defaultIO = SimpleSystemSoundIO(input: NullSystemAudioDevice(), output: factory.someOutput)

        let sut = makeSoundIO(devices: factory.all, settings: settings, defaultIO: defaultIO)

        #expect(sut.output == defaultIO.output)
    }

    @Test func outputIsDefaultOutputWhenSoundOutputUIDFromSettingsCanNotBeFoundInSystemDevices() {
        settings[SettingsKeys.soundOutputUID] = nonexistentDeviceUID
        let defaultIO = SimpleSystemSoundIO(input: NullSystemAudioDevice(), output: factory.someOutput)

        let sut = makeSoundIO(devices: factory.all, settings: settings, defaultIO: defaultIO)

        #expect(sut.output == defaultIO.output)
    }

    @Test func outputIsBuiltInOutputWhenThereIsNoSoundOutputInSettingsAndThereIsNoDefaultOutput() {
        let sut = makeSoundIO()

        #expect(sut.output == factory.firstBuiltInOutput)
    }

    @Test func outputIsBuiltInOutputWhenSoundOutputUIDFromSettingsCanNotBeFoundInSystemDevicesAndThereIsNoDefaultOutput() {
        settings[SettingsKeys.soundOutputUID] = nonexistentDeviceUID

        let sut = makeSoundIO()

        #expect(sut.output == factory.firstBuiltInOutput)
    }

    @Test func outputIsBuiltInOutputWhenAudioDeviceMatchedByUIDFromSettingsDoesNotHaveOutputChannelsAndThereIsNoDefaultOutput() {
        settings[SettingsKeys.soundOutputUID] = factory.inputOnly.uniqueIdentifier

        let sut = makeSoundIO()

        #expect(sut.output == factory.firstBuiltInOutput)
    }

    @Test func outputIsFirstOutputWhenNotFoundInSettingsAndThereIsNoDefaultOutputAndThereIsNoBuiltInOutput() {
        let sut = makeSoundIO(devices: [factory.someInput, factory.firstOutput, factory.someOutput])

        #expect(sut.output == factory.firstOutput)
    }

    // MARK: - Ringtone output

    @Test func ringtoneOutputIsDeviceWithUIDFromSettings() {
        let someDevice = factory.someOutput
        settings[SettingsKeys.ringtoneOutputUID] = someDevice.uniqueIdentifier

        let sut = makeSoundIO()

        #expect(sut.ringtoneOutput == someDevice)
    }

    @Test func ringtoneOutputIsDefaultOutputWhenThereIsNoRingtoneOutputInSettings() {
        let defaultIO = SimpleSystemSoundIO(input: NullSystemAudioDevice(), output: factory.someOutput)

        let sut = makeSoundIO(devices: factory.all, settings: settings, defaultIO: defaultIO)

        #expect(sut.ringtoneOutput == defaultIO.output)
    }

    @Test func ringtoneOutputIsDefaultOutputWhenRingtoneOutputUIDFromSettingsCanNotBeFoundInSystemDevices() {
        settings[SettingsKeys.ringtoneOutputUID] = nonexistentDeviceUID
        let defaultIO = SimpleSystemSoundIO(input: NullSystemAudioDevice(), output: factory.someOutput)

        let sut = makeSoundIO(devices: factory.all, settings: settings, defaultIO: defaultIO)

        #expect(sut.ringtoneOutput == defaultIO.output)
    }

    @Test func ringtoneOutputIsBuiltInOutputWhenThereIsNoRingtoneOutputInSettingsAndThereIsNoDefaultOutput() {
        let sut = makeSoundIO()

        #expect(sut.ringtoneOutput == factory.firstBuiltInOutput)
    }

    @Test func ringtoneOutputIsBuiltInOutputWhenRingtoneOutputUIDFromSettingsCanNotBeFoundInSystemDevicesAndThereIsNoDefaultOutput() {
        settings[SettingsKeys.ringtoneOutputUID] = nonexistentDeviceUID

        let sut = makeSoundIO()

        #expect(sut.ringtoneOutput == factory.firstBuiltInOutput)
    }

    @Test func ringtoneOutputIsBuiltInOutputWhenAudioDeviceMatchedByUIDFromSettingsDoesNotHaveOutputChannelsAndThereIsNoDefaultOutput() {
        settings[SettingsKeys.ringtoneOutputUID] = factory.inputOnly.uniqueIdentifier

        let sut = makeSoundIO()

        #expect(sut.ringtoneOutput == factory.firstBuiltInOutput)
    }

    @Test func ringtoneOutputIsFirstOutputWhenNotFoundInSettingsAndThereIsNoDefaultOutputAndThereIsNoBuiltInOutput() {
        let sut = makeSoundIO(devices: [factory.someInput, factory.firstOutput, factory.someOutput])

        #expect(sut.ringtoneOutput == factory.firstOutput)
    }
}

private extension PreferredSoundIOTests {
    func makeSoundIO(devices: [SystemAudioDevice], settings: KeyValueSettings, defaultIO: SystemSoundIO = NullSystemSoundIO()) -> UseCases.PreferredSoundIO {
        return PreferredSoundIO(
            devices: SystemAudioDevices(devices: devices), settings: settings, defaultIO: defaultIO
        )
    }

    func makeSoundIO(devices: [SystemAudioDevice]) -> UseCases.PreferredSoundIO {
        return makeSoundIO(devices: devices, settings: settings)
    }

    func makeSoundIO() -> UseCases.PreferredSoundIO {
        return makeSoundIO(devices: factory.all)
    }
}

private let nonexistentDeviceUID = "nonexistent-uid"
