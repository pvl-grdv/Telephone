//
//  SoundPresentationProtocols.swift
//  Telephone
//
//  Swift protocols shared by sound presentation code and tests.
//

protocol SoundIOPreferences: AnyObject {
    func updateSoundIO()
}

protocol SoundIOPresenterOutput: AnyObject {
    func update(
        soundIO: PresentationSoundIO,
        devices: PresentationAudioDevices
    )
}

protocol SoundPreferencesView: SoundIOPresenterOutput {}
