//
//  SoundSettingsView.swift
//  Telephone
//

import Cocoa
import Observation

@MainActor
@Observable
final class SoundSettingsModel: NSObject {
    var inputDevices: [PresentationAudioDevice] = []
    var outputDevices: [PresentationAudioDevice] = []
    var selectedInputID = "system-default"
    var selectedOutputID = "system-default"
    var selectedRingtoneOutputID = "system-default"
    var ringtoneNames: [String] = []
    var selectedRingtoneName = ""
    var usesG711Only: Bool

    private let eventTarget: SoundPreferencesViewEventTarget
    private let userAgent: AKSIPUserAgent

    init(eventTarget: SoundPreferencesViewEventTarget, userAgent: AKSIPUserAgent) {
        self.eventTarget = eventTarget
        self.userAgent = userAgent
        usesG711Only = userAgent.usesG711Only
        selectedRingtoneName = UserDefaults.standard.string(forKey: UserDefaultsKeys.ringingSound) ?? ""
        super.init()
    }

    func activate() {
        reloadRingtones()
        usesG711Only = userAgent.usesG711Only
        eventTarget.shouldReloadData(in: self)
    }

    func stopPreview() {
        eventTarget.willDisappear(self)
    }

    func updateSoundIO() {
        eventTarget.shouldReloadSoundIO(in: self)
    }

    func selectInput(_ id: String) {
        selectedInputID = id
        persistSoundIO()
    }

    func selectOutput(_ id: String) {
        selectedOutputID = id
        persistSoundIO()
    }

    func selectRingtoneOutput(_ id: String) {
        selectedRingtoneOutputID = id
        persistSoundIO()
    }

    func selectRingtone(_ name: String) {
        selectedRingtoneName = name
        eventTarget.didChangeRingtoneName(name)
    }

    func setUsesG711Only(_ value: Bool) {
        usesG711Only = value
        UserDefaults.standard.set(value, forKey: UserDefaultsKeys.useG711Only)
        userAgent.usesG711Only = value
    }

    private func persistSoundIO() {
        guard
            let input = inputDevices.first(where: { $0.id == selectedInputID }),
            let output = outputDevices.first(where: { $0.id == selectedOutputID }),
            let ringtoneOutput = outputDevices.first(where: { $0.id == selectedRingtoneOutputID })
        else {
            return
        }

        eventTarget.didChangeSoundIO(
            PresentationSoundIO(input: input, output: output, ringtoneOutput: ringtoneOutput)
        )
    }

    private func reloadRingtones() {
        let paths = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .allDomainsMask, true)
        let extensions: Set<String> = ["aiff", "aif", "aifc", "mp3", "wav", "sd2", "au", "snd", "m4a", "m4p"]
        var names: [String] = []
        var seen = Set<String>()

        for path in paths {
            let soundsPath = URL(fileURLWithPath: path).appendingPathComponent("Sounds")
            let files = (try? FileManager.default.contentsOfDirectory(
                at: soundsPath,
                includingPropertiesForKeys: nil
            )) ?? []

            for file in files where extensions.contains(file.pathExtension.lowercased()) {
                let name = file.deletingPathExtension().lastPathComponent
                if seen.insert(name).inserted {
                    names.append(name)
                }
            }
        }

        ringtoneNames = names
        let saved = UserDefaults.standard.string(forKey: UserDefaultsKeys.ringingSound) ?? ""
        if names.contains(saved) {
            selectedRingtoneName = saved
        } else if let first = names.first {
            selectedRingtoneName = first
        }
    }
}

extension SoundSettingsModel: SoundPreferencesView {
    func update(soundIO: PresentationSoundIO, devices: PresentationAudioDevices) {
        inputDevices = devices.input
        outputDevices = devices.output
        selectedInputID = soundIO.input.id
        selectedOutputID = soundIO.output.id
        selectedRingtoneOutputID = soundIO.ringtoneOutput.id
    }
}

