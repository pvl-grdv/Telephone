//
//  SettingsViewController.swift
//  Telephone
//

import Cocoa
import Observation
import SwiftUI

@MainActor
@objcMembers
final class SettingsViewController: NSViewController {
    private let model: SettingsViewModel

    @objc(initWithAccountPreferencesViewController:soundEventTarget:userAgent:preferencesController:)
    init(
        accountPreferencesViewController: AccountPreferencesViewController,
        soundEventTarget: SoundPreferencesViewEventTarget,
        userAgent: AKSIPUserAgent,
        preferencesController: PreferencesController
    ) {
        model = SettingsViewModel(
            accountPreferencesViewController: accountPreferencesViewController,
            soundModel: SoundSettingsModel(eventTarget: soundEventTarget, userAgent: userAgent),
            networkModel: NetworkSettingsModel(
                userAgent: userAgent,
                preferencesController: preferencesController
            )
        )
        super.init(nibName: nil, bundle: nil)
        model.closeWindow = { [weak self] in
            self?.view.window?.performClose(nil)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSHostingView(rootView: SettingsRootView(model: model))
    }

    func showAccounts() {
        model.requestSelection(.accounts)
    }

    func updateSoundIO() {
        model.soundModel.updateSoundIO()
    }

    func requestWindowClose() -> Bool {
        model.requestWindowClose()
    }
}

private enum SettingsSection: Int, CaseIterable, Hashable {
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
private final class SettingsViewModel {
    var selection: SettingsSection = .general
    var showsNetworkSavePrompt = false

    let accountPreferencesViewController: AccountPreferencesViewController
    let soundModel: SoundSettingsModel
    let networkModel: NetworkSettingsModel

    var closeWindow: (() -> Void)?

    private var pendingTransition: PendingSettingsTransition?

    init(
        accountPreferencesViewController: AccountPreferencesViewController,
        soundModel: SoundSettingsModel,
        networkModel: NetworkSettingsModel
    ) {
        self.accountPreferencesViewController = accountPreferencesViewController
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

private struct SettingsRootView: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        TabView(selection: selection) {
            GeneralSettingsView()
                .tabItem { Label(SettingsSection.general.title, systemImage: SettingsSection.general.systemImage) }
                .tag(SettingsSection.general)

            LegacyAccountSettingsView(controller: model.accountPreferencesViewController)
                .tabItem { Label(SettingsSection.accounts.title, systemImage: SettingsSection.accounts.systemImage) }
                .tag(SettingsSection.accounts)

            SoundSettingsView(model: model.soundModel)
                .tabItem { Label(SettingsSection.sound.title, systemImage: SettingsSection.sound.systemImage) }
                .tag(SettingsSection.sound)

            NetworkSettingsView(model: model.networkModel)
                .tabItem { Label(SettingsSection.network.title, systemImage: SettingsSection.network.systemImage) }
                .tag(SettingsSection.network)
        }
        .frame(minWidth: 650, idealWidth: 720, minHeight: 480, idealHeight: 560)
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

private struct LegacyAccountSettingsView: NSViewControllerRepresentable {
    let controller: AccountPreferencesViewController

    func makeNSViewController(context: Context) -> AccountPreferencesViewController {
        controller
    }

    func updateNSViewController(_ nsViewController: AccountPreferencesViewController, context: Context) {}
}
