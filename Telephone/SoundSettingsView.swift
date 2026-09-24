//
//  SoundSettingsView.swift
//  Telephone
//

import Cocoa
import Observation
import SwiftUI

@MainActor
@Observable
final class SoundSettingsModel: NSObject {
    var inputDevices: [PresentationAudioDevice] = []
    var outputDevices: [PresentationAudioDevice] = []
    var selectedInputName = ""
    var selectedOutputName = ""
    var selectedRingtoneOutputName = ""
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

    func selectInput(_ name: String) {
        selectedInputName = name
        persistSoundIO()
    }

    func selectOutput(_ name: String) {
        selectedOutputName = name
        persistSoundIO()
    }

    func selectRingtoneOutput(_ name: String) {
        selectedRingtoneOutputName = name
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
            let input = inputDevices.first(where: { $0.name == selectedInputName }),
            let output = outputDevices.first(where: { $0.name == selectedOutputName }),
            let ringtoneOutput = outputDevices.first(where: { $0.name == selectedRingtoneOutputName })
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
        selectedInputName = soundIO.input.name
        selectedOutputName = soundIO.output.name
        selectedRingtoneOutputName = soundIO.ringtoneOutput.name
    }
}

struct SoundSettingsView: View {
    @Bindable var model: SoundSettingsModel

    var body: some View {
        Form {
            Section {
                Picker(
                    NSLocalizedString("Sound Input", comment: "Sound settings label."),
                    selection: inputSelection
                ) {
                    ForEach(model.inputDevices) { device in
                        Text(device.name).tag(device.name)
                    }
                }

                Picker(
                    NSLocalizedString("Sound Output", comment: "Sound settings label."),
                    selection: outputSelection
                ) {
                    ForEach(model.outputDevices) { device in
                        Text(device.name).tag(device.name)
                    }
                }

                Picker(
                    NSLocalizedString("Ringtone Output", comment: "Sound settings label."),
                    selection: ringtoneOutputSelection
                ) {
                    ForEach(model.outputDevices) { device in
                        Text(device.name).tag(device.name)
                    }
                }
            }

            Section {
                Picker(
                    NSLocalizedString("Ringtone", comment: "Sound settings label."),
                    selection: ringtoneSelection
                ) {
                    ForEach(model.ringtoneNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .disabled(model.ringtoneNames.isEmpty)

                Text(
                    NSLocalizedString(
                        "Place ringtones in ~/Library/Sounds",
                        comment: "Sound settings help text."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    NSLocalizedString("Use only G.711 codec", comment: "Sound settings toggle."),
                    isOn: g711Selection
                )
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { model.activate() }
        .onDisappear { model.stopPreview() }
    }

    private var inputSelection: Binding<String> {
        Binding(get: { model.selectedInputName }, set: model.selectInput)
    }

    private var outputSelection: Binding<String> {
        Binding(get: { model.selectedOutputName }, set: model.selectOutput)
    }

    private var ringtoneOutputSelection: Binding<String> {
        Binding(get: { model.selectedRingtoneOutputName }, set: model.selectRingtoneOutput)
    }

    private var ringtoneSelection: Binding<String> {
        Binding(get: { model.selectedRingtoneName }, set: model.selectRingtone)
    }

    private var g711Selection: Binding<Bool> {
        Binding(get: { model.usesG711Only }, set: model.setUsesG711Only)
    }
}
