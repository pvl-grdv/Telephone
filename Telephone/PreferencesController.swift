//
//  PreferencesController.swift
//  Telephone
//

import SwiftUI

@MainActor
final class PreferencesController: SoundIOPreferences {
    weak var delegate: PreferencesControllerDelegate?

    let userAgent: AKSIPUserAgent
    let soundPreferencesViewEventTarget: SoundPreferencesViewEventTarget
    let crmGatewaySettings: CRMGatewaySettings

    private var notificationObservations: [NotificationObservation] = []

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
        },
        crmModelFactory: { [unowned self] in
            CRMGatewaySettingsModel(settings: crmGatewaySettings)
        }
    )

    init(
        delegate: PreferencesControllerDelegate,
        userAgent: AKSIPUserAgent,
        soundPreferencesViewEventTarget: SoundPreferencesViewEventTarget,
        crmGatewaySettings: CRMGatewaySettings = CRMGatewaySettings()
    ) {
        self.delegate = delegate
        self.userAgent = userAgent
        self.soundPreferencesViewEventTarget = soundPreferencesViewEventTarget
        self.crmGatewaySettings = crmGatewaySettings

        observePreferenceChanges()
    }

    func showSettings() {
        PerformanceSignposts.settings.emitEvent("OpenSettingsRequested")
        SceneRouter.shared.openSettings()
    }

#if DEBUG
    func showWindowForUITesting() {
        SceneRouter.shared.openWindow(id: PreferencesUITestScene.id)
    }
#endif

    var sceneModel: SettingsViewModel {
        model
    }

    func showAccounts() {
        model.selection = .accounts
    }

    func reloadAccount(at index: Int) {
        model.reloadAccountIfLoaded(at: index)
    }

    func updateSoundIO() {
        model.updateSoundIOIfLoaded()
    }

    private func observePreferenceChanges() {
        observe(
            .AKPreferencesControllerDidRemoveAccount
        ) { [weak self] notification in
            self?.delegate?.preferencesControllerDidRemoveAccount(notification)
        }
        observe(
            .AKPreferencesControllerDidChangeAccountEnabled
        ) { [weak self] notification in
            self?.delegate?.preferencesControllerDidChangeAccountEnabled(
                notification
            )
        }
        observe(
            .AKPreferencesControllerDidSwapAccounts
        ) { [weak self] notification in
            self?.delegate?.preferencesControllerDidSwapAccounts(notification)
        }
        observe(
            .AKPreferencesControllerDidChangeNetworkSettings
        ) { [weak self] notification in
            self?.delegate?.preferencesControllerDidChangeNetworkSettings(
                notification
            )
        }
    }

    private func observe(
        _ name: Notification.Name,
        action: @escaping @MainActor (Notification) -> Void
    ) {
        notificationObservations.append(
            NotificationObservation(
                name: name,
                object: self
            ) { notification in
                let notification =
                    PreferencesSendableNotification(notification)
                MainActor.assumeIsolated {
                    action(notification.value)
                }
            }
        )
    }
}

private struct PreferencesSendableNotification: @unchecked Sendable {
    let value: Notification

    init(_ value: Notification) {
        self.value = value
    }
}


struct PreferencesHostedScene: Scene {
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

#if DEBUG

struct PreferencesUITestHostedScene: Scene {
    let model: SettingsViewModel

    var body: some Scene {
        Window(
            NSLocalizedString(
                "Telephone Settings",
                comment: "Settings default window title."
            ),
            id: PreferencesUITestScene.id
        ) {
            SettingsRootView(
                model: model,
                selectionChanged: { _ in }
            )
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 600, height: 330)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .windowIdealSize(.fitToContent)
        .commandsRemoved()
    }
}

enum PreferencesUITestScene {
    static let id = "telephone-ui-test-settings"
}

#endif
