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

private enum PendingSettingsTransition {
    case selection(SettingsSection)
    case close
}

@MainActor
@Observable
final class SettingsViewModel {
    var selection: SettingsSection = .general
    var showsNetworkSavePrompt = false
    var showsAccountSetup = false

    let accountModel: AccountSettingsModel
    let soundModel: SoundSettingsModel
    let networkModel: NetworkSettingsModel

    var closeWindow: (() -> Void)?

    private var pendingTransition: PendingSettingsTransition?

    init(
        accountModel: AccountSettingsModel,
        soundModel: SoundSettingsModel,
        networkModel: NetworkSettingsModel
    ) {
        self.accountModel = accountModel
        self.soundModel = soundModel
        self.networkModel = networkModel
    }

    func requestSelection(_ section: SettingsSection) {
        guard section != selection else { return }

        if selection == .network && networkModel.hasChanges {
            pendingTransition = .selection(section)
            showsNetworkSavePrompt = true
        } else {
            selection = section
        }
    }

    func requestWindowClose() -> Bool {
        if selection == .network && networkModel.hasChanges {
            pendingTransition = .close
            showsNetworkSavePrompt = true
            return false
        }
        soundModel.stopPreview()
        return true
    }

    func saveNetworkAndContinue() {
        networkModel.save()
        completePendingTransition()
    }

    func discardNetworkAndContinue() {
        networkModel.discard()
        completePendingTransition()
    }

    func cancelPendingTransition() {
        pendingTransition = nil
        showsNetworkSavePrompt = false
    }

    private func completePendingTransition() {
        let transition = pendingTransition
        pendingTransition = nil
        showsNetworkSavePrompt = false

        switch transition {
        case .selection(let section):
            selection = section
        case .close:
            soundModel.stopPreview()
            closeWindow?()
        case nil:
            break
        }
    }
}

struct SettingsRootView: View {
    @Bindable var model: SettingsViewModel
    let selectionChanged: (SettingsSection) -> Void

    var body: some View {
        TabView(selection: selection) {
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
        .alert(
            NSLocalizedString(
                "Save changes to the network settings?",
                comment: "Network settings change confirmation."
            ),
            isPresented: $model.showsNetworkSavePrompt
        ) {
            Button(NSLocalizedString("Save", comment: "Save button.")) {
                model.saveNetworkAndContinue()
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel button."), role: .cancel) {
                model.cancelPendingTransition()
            }
            Button(NSLocalizedString("Don't Save", comment: "Don't save button."), role: .destructive) {
                model.discardNetworkAndContinue()
            }
        } message: {
            Text(
                NSLocalizedString(
                    "New network settings will be applied immediately, all accounts will be reconnected.",
                    comment: "Network settings change confirmation informative text."
                )
            )
        }
    }

    private var selection: Binding<SettingsSection> {
        Binding(
            get: { model.selection },
            set: { model.requestSelection($0) }
        )
    }
}
