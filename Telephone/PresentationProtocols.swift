//
//  PresentationProtocols.swift
//  Telephone
//
//  Small Swift protocols used by presentation controllers.
//

import Foundation

@MainActor
protocol CallControllerDelegate: AnyObject {
    func callControllerWillClose(_ callController: CallController)
}

@MainActor
protocol PreferencesControllerDelegate: AnyObject {
    func preferencesControllerDidRemoveAccount(_ notification: Notification)
    func preferencesControllerDidChangeAccountEnabled(
        _ notification: Notification
    )
    func preferencesControllerDidSwapAccounts(_ notification: Notification)
    func preferencesControllerDidChangeNetworkSettings(
        _ notification: Notification
    )
}

extension PreferencesControllerDelegate {
    func preferencesControllerDidRemoveAccount(_ notification: Notification) {}
    func preferencesControllerDidChangeAccountEnabled(
        _ notification: Notification
    ) {}
    func preferencesControllerDidSwapAccounts(_ notification: Notification) {}
    func preferencesControllerDidChangeNetworkSettings(
        _ notification: Notification
    ) {}
}

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
