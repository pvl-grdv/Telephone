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

    private var fallbackWindowController: NSWindowController?
    private var modernController: AnyObject?

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

        super.init()

        observePreferenceChanges()
    }

    func install() {
        if #available(macOS 26.0, *) {
            let controller = PreferencesSceneController(model: model)
            modernController = controller
            controller.install()
        }
    }

    func showWindowCentered() {
        if #available(macOS 26.0, *),
           let controller = modernController as? PreferencesSceneController {
            controller.show()
            return
        }

        let controller = fallbackWindowController
            ?? makeFallbackWindowController()
        fallbackWindowController = controller

        guard let window = controller.window else { return }
        if !window.isVisible {
            window.center()
        }
        controller.showWindow(nil)
    }

    func showAccounts() {
        model.selection = .accounts
    }

    @objc(reloadAccountAtIndex:)
    func reloadAccount(at index: Int) {
        model.accountModel.reloadAccount(at: index)
    }

    func updateSoundIO() {
        model.soundModel.updateSoundIO()
    }

    private func dismissFallbackWindow() {
        fallbackWindowController?.close()
        fallbackWindowController = nil
    }

    private func makeFallbackWindowController() -> NSWindowController {
        let rootView = SettingsRootView(
            model: model,
            selectionChanged: { [weak self] section in
                self?.fallbackWindowController?.window?.title = section.title
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
        settingsWindow.setContentSize(contentController.view.fittingSize)
        return NSWindowController(window: settingsWindow)
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


@available(macOS 26.0, *)
private struct PreferencesHostedScene: Scene {
    let model: SettingsViewModel

    var body: some Scene {
        Settings {
            SettingsRootView(
                model: model,
                selectionChanged: { _ in }
            )
        }
    }
}

@available(macOS 26.0, *)
@MainActor
private final class PreferencesSceneController {
    private let representation:
        NSHostingSceneRepresentation<PreferencesHostedScene>

    init(model: SettingsViewModel) {
        representation = NSHostingSceneRepresentation {
            PreferencesHostedScene(model: model)
        }
    }

    func install() {
        NSApplication.shared.addSceneRepresentation(representation)
    }

    func show() {
        representation.environment.openSettings()
    }
}
