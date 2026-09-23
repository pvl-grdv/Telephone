//
//  PreferencesController.swift
//  Telephone
//

import AppKit
import SwiftUI

@MainActor
@objcMembers
final class PreferencesController: NSWindowController, NSWindowDelegate, SoundIOPreferences {
    weak var delegate: PreferencesControllerDelegate?

    let userAgent: AKSIPUserAgent
    let soundPreferencesViewEventTarget: SoundPreferencesViewEventTarget

    private lazy var model: SettingsViewModel = {
        let accountModel = AccountSettingsModel(preferencesController: self)
        let model = SettingsViewModel(
            accountModel: accountModel,
            soundModel: SoundSettingsModel(
                eventTarget: soundPreferencesViewEventTarget,
                userAgent: userAgent
            ),
            networkModel: NetworkSettingsModel(
                userAgent: userAgent,
                preferencesController: self
            )
        )

        model.closeWindow = { [weak self] in
            self?.window?.performClose(nil)
        }
        accountModel.presentAddAccount = { [weak model] in
            model?.showsAccountSetup = true
        }
        return model
    }()

    @objc(initWithDelegate:userAgent:soundPreferencesViewEventTarget:)
    init(
        delegate: PreferencesControllerDelegate,
        userAgent: AKSIPUserAgent,
        soundPreferencesViewEventTarget: SoundPreferencesViewEventTarget
    ) {
        self.delegate = delegate
        self.userAgent = userAgent
        self.soundPreferencesViewEventTarget = soundPreferencesViewEventTarget

        super.init(window: nil)

        let rootView = SettingsRootView(
            model: model,
            selectionChanged: { [weak self] section in
                self?.window?.title = section.title
            }
        )
        let contentController = NSHostingController(rootView: rootView)

        let settingsWindow = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = NSLocalizedString(
            "Telephone Settings",
            comment: "Settings default window title."
        )
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.contentViewController = contentController
        settingsWindow.delegate = self
        settingsWindow.setContentSize(contentController.view.fittingSize)
        window = settingsWindow

        observePreferenceChanges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowCentered() {
        guard let window else { return }

        if !window.isVisible {
            window.center()
        }
        showWindow(nil)
    }

    func showAccounts() {
        model.requestSelection(.accounts)
    }

    @objc(reloadAccountAtIndex:)
    func reloadAccount(at index: Int) {
        model.accountModel.reloadAccount(at: index)
    }

    func updateSoundIO() {
        model.soundModel.updateSoundIO()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.requestWindowClose()
    }

    private func observePreferenceChanges() {
        let center = NotificationCenter.default

        center.addObserver(
            self,
            selector: #selector(accountDidRemove(_:)),
            name: .AKPreferencesControllerDidRemoveAccount,
            object: self
        )
        center.addObserver(
            self,
            selector: #selector(accountEnabledDidChange(_:)),
            name: .AKPreferencesControllerDidChangeAccountEnabled,
            object: self
        )
        center.addObserver(
            self,
            selector: #selector(accountsDidSwap(_:)),
            name: .AKPreferencesControllerDidSwapAccounts,
            object: self
        )
        center.addObserver(
            self,
            selector: #selector(networkSettingsDidChange(_:)),
            name: .AKPreferencesControllerDidChangeNetworkSettings,
            object: self
        )
    }

    @objc private func accountDidRemove(_ notification: Notification) {
        delegate?.preferencesControllerDidRemoveAccount?(notification)
    }

    @objc private func accountEnabledDidChange(_ notification: Notification) {
        delegate?.preferencesControllerDidChangeAccountEnabled?(notification)
    }

    @objc private func accountsDidSwap(_ notification: Notification) {
        delegate?.preferencesControllerDidSwapAccounts?(notification)
    }

    @objc private func networkSettingsDidChange(_ notification: Notification) {
        delegate?.preferencesControllerDidChangeNetworkSettings?(notification)
    }
}
