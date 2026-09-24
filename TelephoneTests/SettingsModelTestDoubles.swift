//
//  SettingsModelTestDoubles.swift
//  TelephoneTests
//

@MainActor
final class SoundSettingsModel {
    func updateSoundIO() {}
    func stopPreview() {}
}

@MainActor
final class NetworkSettingsModel {
    func discard() {}
}
