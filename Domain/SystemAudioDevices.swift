//
//  SystemAudioDevices.swift
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

public struct SystemAudioDevices {
    public let all: [SystemAudioDevice]
    public let input: [SystemAudioDevice]
    public let output: [SystemAudioDevice]

    private let inputByUniqueIdentifier: [String: SystemAudioDevice]
    private let outputByUniqueIdentifier: [String: SystemAudioDevice]
    private let inputByName: [String: SystemAudioDevice]
    private let outputByName: [String: SystemAudioDevice]

    public init(devices: [SystemAudioDevice]) {
        all = devices
        input = devices.filter(\.hasInputs)
        output = devices.filter(\.hasOutputs)
        inputByUniqueIdentifier = deviceMap(
            from: input,
            key: \.uniqueIdentifier
        )
        outputByUniqueIdentifier = deviceMap(
            from: output,
            key: \.uniqueIdentifier
        )
        inputByName = deviceMap(from: input, key: \.name)
        outputByName = deviceMap(from: output, key: \.name)
    }

    public func inputDevice(
        uniqueIdentifier: String
    ) -> SystemAudioDevice {
        inputByUniqueIdentifier[uniqueIdentifier]
            ?? NullSystemAudioDevice()
    }

    public func outputDevice(
        uniqueIdentifier: String
    ) -> SystemAudioDevice {
        outputByUniqueIdentifier[uniqueIdentifier]
            ?? NullSystemAudioDevice()
    }

    public func inputDevice(named name: String) -> SystemAudioDevice {
        inputByName[name] ?? NullSystemAudioDevice()
    }

    public func outputDevice(named name: String) -> SystemAudioDevice {
        outputByName[name] ?? NullSystemAudioDevice()
    }
}

private func deviceMap(
    from devices: [SystemAudioDevice],
    key: KeyPath<any SystemAudioDevice, String>
) -> [String: SystemAudioDevice] {
    devices.reduce(into: [:]) { result, device in
        result[device[keyPath: key]] = device
    }
}
