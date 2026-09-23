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
    var selection: SettingsSection {
        didSet {
            defaults.set(
                selection.rawValue,
                forKey: UserDefaultsKeys.settingsSection
            )
        }
    }
    var showsAccountSetup = false

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let accountModelFactory: () -> AccountSettingsModel
    @ObservationIgnored
    private let soundModelFactory: () -> SoundSettingsModel
    @ObservationIgnored
    private let networkModelFactory: () -> NetworkSettingsModel

    @ObservationIgnored
    private var storedAccountModel: AccountSettingsModel?
    @ObservationIgnored
    private var storedSoundModel: SoundSettingsModel?
    @ObservationIgnored
    private var storedNetworkModel: NetworkSettingsModel?

    init(
        defaults: UserDefaults = .standard,
        accountModelFactory: @escaping () -> AccountSettingsModel,
        soundModelFactory: @escaping () -> SoundSettingsModel,
        networkModelFactory: @escaping () -> NetworkSettingsModel
    ) {
        self.defaults = defaults
        self.accountModelFactory = accountModelFactory
        self.soundModelFactory = soundModelFactory
        self.networkModelFactory = networkModelFactory

        let rawValue = defaults.integer(
            forKey: UserDefaultsKeys.settingsSection
        )
        selection = SettingsSection(rawValue: rawValue) ?? .general
    }

    var accountModel: AccountSettingsModel {
        if let storedAccountModel {
            return storedAccountModel
        }

        let interval = PerformanceSignposts.settings.beginInterval(
            "CreateAccountsSettingsModel"
        )
        let model = accountModelFactory()
        model.presentAddAccount = { [weak self] in
            self?.showsAccountSetup = true
        }
        storedAccountModel = model
        PerformanceSignposts.settings.endInterval(
            "CreateAccountsSettingsModel",
            interval
        )
        return model
    }

    var soundModel: SoundSettingsModel {
        if let storedSoundModel {
            return storedSoundModel
        }

        let interval = PerformanceSignposts.settings.beginInterval(
            "CreateSoundSettingsModel"
        )
        let model = soundModelFactory()
        storedSoundModel = model
        PerformanceSignposts.settings.endInterval(
            "CreateSoundSettingsModel",
            interval
        )
        return model
    }

    var networkModel: NetworkSettingsModel {
        if let storedNetworkModel {
            return storedNetworkModel
        }

        let interval = PerformanceSignposts.settings.beginInterval(
            "CreateNetworkSettingsModel"
        )
        let model = networkModelFactory()
        storedNetworkModel = model
        PerformanceSignposts.settings.endInterval(
            "CreateNetworkSettingsModel",
            interval
        )
        return model
    }

    func reloadAccountIfLoaded(at index: Int) {
        storedAccountModel?.reloadAccount(at: index)
    }

    func updateSoundIOIfLoaded() {
        storedSoundModel?.updateSoundIO()
    }

    func prepareToClose() {
        storedAccountModel?.flushPendingChanges()
        storedSoundModel?.stopPreview()
        storedNetworkModel?.discard()
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
                if model.selection == .accounts {
                    AccountSettingsView(model: model.accountModel)
                } else {
                    Color.clear
                }
            } label: {
                Label(
                    SettingsSection.accounts.title,
                    systemImage: SettingsSection.accounts.systemImage
                )
            }

            Tab(value: SettingsSection.sound) {
                if model.selection == .sound {
                    SoundSettingsView(model: model.soundModel)
                } else {
                    Color.clear
                }
            } label: {
                Label(
                    SettingsSection.sound.title,
                    systemImage: SettingsSection.sound.systemImage
                )
            }

            Tab(value: SettingsSection.network) {
                if model.selection == .network {
                    NetworkSettingsView(model: model.networkModel)
                } else {
                    Color.clear
                }
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
            PerformanceSignposts.settings.emitEvent(
                "SettingsSectionChanged",
                "\(selection.rawValue)"
            )
            selectionChanged(selection)
        }
        .onAppear {
            PerformanceSignposts.settings.emitEvent("SettingsVisible")
        }
        .onDisappear {
            model.prepareToClose()
        }

}
}
