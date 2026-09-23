//
//  SettingsView.swift
//  Telephone
//

import Observation
import SwiftUI

enum SettingsSection: Int, CaseIterable, Hashable {
    case general
    case accounts
    case sound
    case network

    var title: String {
        switch self {
        case .general:
            NSLocalizedString("General", comment: "General preferences window title.")
        case .accounts:
            NSLocalizedString("Accounts", comment: "Accounts preferences window title.")
        case .sound:
            NSLocalizedString("Sound", comment: "Sound preferences window title.")
        case .network:
            NSLocalizedString("Network", comment: "Network preferences window title.")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .accounts: "at"
        case .sound: "speaker.wave.2"
        case .network: "network"
        }
    }
}

@MainActor
@Observable
final class SettingsViewModel {
    var selection: SettingsSection = .general
    var showsAccountSetup = false

    let accountModel: AccountSettingsModel
    let soundModel: SoundSettingsModel
    let networkModel: NetworkSettingsModel

    init(
        accountModel: AccountSettingsModel,
        soundModel: SoundSettingsModel,
        networkModel: NetworkSettingsModel
    ) {
        self.accountModel = accountModel
        self.soundModel = soundModel
        self.networkModel = networkModel
    }

    func prepareToClose() {
        soundModel.stopPreview()
        networkModel.discard()
    }
}
struct SettingsRootView: View {
    @Bindable var model: SettingsViewModel
    let selectionChanged: (SettingsSection) -> Void

    var body: some View {
        TabView(selection: $model.selection) {
            Tab(value: SettingsSection.general) {
                GeneralSettingsView()
            } label: {
                Label(
                    SettingsSection.general.title,
                    systemImage: SettingsSection.general.systemImage
                )
            }

            Tab(value: SettingsSection.accounts) {
                AccountSettingsView(model: model.accountModel)
            } label: {
                Label(
                    SettingsSection.accounts.title,
                    systemImage: SettingsSection.accounts.systemImage
                )
            }

            Tab(value: SettingsSection.sound) {
                SoundSettingsView(model: model.soundModel)
            } label: {
                Label(
                    SettingsSection.sound.title,
                    systemImage: SettingsSection.sound.systemImage
                )
            }

            Tab(value: SettingsSection.network) {
                NetworkSettingsView(model: model.networkModel)
            } label: {
                Label(
                    SettingsSection.network.title,
                    systemImage: SettingsSection.network.systemImage
                )
            }
        }
        .frame(
            minWidth: 650,
            idealWidth: 720,
            minHeight: 480,
            idealHeight: 560
        )
        .sheet(isPresented: $model.showsAccountSetup) {
            AccountSetupSheet()
        }
        .onChange(of: model.selection, initial: true) { _, selection in
            selectionChanged(selection)
        }
        .onDisappear {
            model.prepareToClose()
        }

}
}
