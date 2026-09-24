//
//  SoundSettingsView.swift
//  Telephone
//

import SwiftUI

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
                        Text(device.name).tag(device.id)
                    }
                }

                Picker(
                    NSLocalizedString("Sound Output", comment: "Sound settings label."),
                    selection: outputSelection
                ) {
                    ForEach(model.outputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }

                Picker(
                    NSLocalizedString("Ringtone Output", comment: "Sound settings label."),
                    selection: ringtoneOutputSelection
                ) {
                    ForEach(model.outputDevices) { device in
                        Text(device.name).tag(device.id)
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
        Binding(get: { model.selectedInputID }, set: model.selectInput)
    }

    private var outputSelection: Binding<String> {
        Binding(get: { model.selectedOutputID }, set: model.selectOutput)
    }

    private var ringtoneOutputSelection: Binding<String> {
        Binding(get: { model.selectedRingtoneOutputID }, set: model.selectRingtoneOutput)
    }

    private var ringtoneSelection: Binding<String> {
        Binding(get: { model.selectedRingtoneName }, set: model.selectRingtone)
    }

    private var g711Selection: Binding<Bool> {
        Binding(get: { model.usesG711Only }, set: model.setUsesG711Only)
    }
}
