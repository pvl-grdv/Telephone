//
//  SettingsViewController.swift
//  Telephone
//

import AppKit
import SwiftUI

@MainActor
@objcMembers
final class SettingsViewController: NSViewController {
    private let model: SettingsViewModel

    @objc(initWithSoundEventTarget:userAgent:preferencesController:)
    init(
        soundEventTarget: SoundPreferencesViewEventTarget,
        userAgent: AKSIPUserAgent,
        preferencesController: PreferencesController
    ) {
        let accountModel = AccountSettingsModel(
            preferencesController: preferencesController
        )
        let model = SettingsViewModel(
            accountModel: accountModel,
            soundModel: SoundSettingsModel(
                eventTarget: soundEventTarget,
                userAgent: userAgent
            ),
            networkModel: NetworkSettingsModel(
                userAgent: userAgent,
                preferencesController: preferencesController
            )
        )
        self.model = model

        super.init(nibName: nil, bundle: nil)

        model.closeWindow = { [weak self] in
            self?.view.window?.performClose(nil)
        }
        accountModel.presentAddAccount = { [weak model] in
            model?.showsAccountSetup = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSHostingView(
            rootView: SettingsRootView(
                model: model,
                selectionChanged: { [weak self] section in
                    self?.view.window?.title = section.title
                }
            )
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.title = model.selection.title
    }

    func showAccounts() {
        model.requestSelection(.accounts)
    }

    func updateSoundIO() {
        model.soundModel.updateSoundIO()
    }

    func reloadAccount(at index: Int) {
        model.accountModel.reloadAccount(at: index)
    }

    func requestWindowClose() -> Bool {
        model.requestWindowClose()
    }
}
