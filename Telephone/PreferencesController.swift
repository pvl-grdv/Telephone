//
//  PreferencesController.swift
//  Telephone
//

import AppKit
import SwiftUI

@MainActor
@objcMembers
final class PreferencesController: NSObject, SoundIOPreferences {
    weak var delegate: PreferencesControllerDelegate?

    let userAgent: AKSIPUserAgent
    let soundPreferencesViewEventTarget: SoundPreferencesViewEventTarget

    private lazy var sceneController = PreferencesSceneController(model: model)

    private lazy var model = SettingsViewModel(
        accountModelFactory: { [unowned self] in
            AccountSettingsModel(preferencesController: self)
        },
        soundModelFactory: { [unowned self] in
            SoundSettingsModel(
                eventTarget: soundPreferencesViewEventTarget,
                userAgent: userAgent
            )
        },
        networkModelFactory: { [unowned self] in
            NetworkSettingsModel(
                userAgent: userAgent,
                preferencesController: self
            )
        }
    )

    @objc(initWithDelegate:userAgent:soundPreferencesViewEventTarget:)
    init(
        delegate: PreferencesControllerDelegate,
        userAgent: AKSIPUserAgent,
        soundPreferencesViewEventTarget: SoundPreferencesViewEventTarget
    ) {
        self.delegate = delegate
        self.userAgent = userAgent
        self.soundPreferencesViewEventTarget = soundPreferencesViewEventTarget

        super.init()

        observePreferenceChanges()
    }

    func install() {
        sceneController.install()
    }

    func showWindowCentered() {
        PerformanceSignposts.settings.emitEvent("OpenSettingsRequested")
        sceneController.show()
    }

    func showAccounts() {
        model.selection = .accounts
    }

    @objc(reloadAccountAtIndex:)
    func reloadAccount(at index: Int) {
        model.reloadAccountIfLoaded(at: index)
    }

    func updateSoundIO() {
        model.updateSoundIOIfLoaded()
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


private struct PreferencesHostedScene: Scene {
    let model: SettingsViewModel

    var body: some Scene {
        Settings {
            SettingsRootView(
                model: model,
                selectionChanged: { _ in }
            )
        }
        .defaultSize(width: 600, height: 330)
        .windowResizability(.contentSize)
        .windowIdealSize(.fitToContent)
    }
}

@MainActor
private final class PreferencesSceneController {
    private let representation:
        NSHostingSceneRepresentation<PreferencesHostedScene>
    private var installed = false

    init(model: SettingsViewModel) {
        representation = NSHostingSceneRepresentation {
            PreferencesHostedScene(model: model)
        }
    }

    func install() {
        guard !installed else { return }
        installed = true
        NSApplication.shared.addSceneRepresentation(representation)
    }

    func show() {
        install()
        representation.environment.openSettings()
    }
}
