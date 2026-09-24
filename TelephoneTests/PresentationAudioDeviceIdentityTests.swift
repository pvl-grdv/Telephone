//
//  PresentationAudioDeviceIdentityTests.swift
//  TelephoneTests
//

import Domain
import Testing

struct PresentationAudioDeviceIdentityTests {
    @Test func coreAudioUIDDefinesPresentationIdentity() {
        let first = SimpleSystemAudioDevice(
            identifier: 1,
            uniqueIdentifier: "device-uid-1",
            name: "USB Audio",
            inputs: 1,
            outputs: 1,
            isBuiltIn: false
        )
        let second = SimpleSystemAudioDevice(
            identifier: 2,
            uniqueIdentifier: "device-uid-2",
            name: "USB Audio",
            inputs: 1,
            outputs: 1,
            isBuiltIn: false
        )

        let firstPresentation = PresentationAudioDevice(device: first)
        let secondPresentation = PresentationAudioDevice(device: second)

        #expect(firstPresentation.id == "coreaudio:device-uid-1")
        #expect(secondPresentation.id == "coreaudio:device-uid-2")
        #expect(firstPresentation.id != secondPresentation.id)
    }

    @Test func systemDefaultIdentityIsStable() {
        let first = PresentationAudioDevice(
            isSystemDefault: true,
            name: "Use System Setting"
        )
        let second = PresentationAudioDevice(
            isSystemDefault: true,
            name: "Use System Setting"
        )

        #expect(first.id == second.id)
    }
}
