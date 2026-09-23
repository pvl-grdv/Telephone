//
//  AccountWindowController.swift
//  Telephone
//

import AppKit
import SwiftUI
import UseCases

@objc enum AccountWindowControllerAccountState: Int {
    case offline
    case available
    case unavailable
}

@objc protocol AccountWindowControllerDelegate: AnyObject {
    func accountWindowController(
        _ controller: AccountWindowController,
        didChangeAccountState state: AccountWindowControllerAccountState
    )
}

@MainActor
@objcMembers
final class AccountWindowController: NSObject {
    private let accountDescription: String
    private let windowKey: String
    private let callDestinationComposer: CallDestinationComposer
    private let callHistoryPresenter: CallHistoryPresenter
    private let callHistoryViewEventTargetFactory: AsyncCallHistoryViewEventTargetFactory
    private let account: Account
    private let authenticationFailureController: AuthenticationFailureController
    private weak var accountDelegate: AccountWindowControllerDelegate?
    private let model = AccountWindowModel()

    private var callHistoryViewEventTarget: CallHistoryViewEventTarget?

    var canMakeCalls: Bool {
        model.showsCallComposer
    }

    class func installScene() {
        AccountWindowSceneController.shared.install()
    }

    @objc(initWithAccountDescription:accountController:userAgent:callHistoryViewEventTargetFactory:account:delegate:)
    init(
        accountDescription: String,
        accountController: AccountController,
        userAgent: AKSIPUserAgent,
        callHistoryViewEventTargetFactory: AsyncCallHistoryViewEventTargetFactory,
        account: Account,
        delegate: AccountWindowControllerDelegate
    ) {
        self.accountDescription = accountDescription
        windowKey = account.uuid
        callDestinationComposer = CallDestinationComposer(
            accountController: accountController
        )
        callHistoryPresenter = CallHistoryPresenter()
        self.callHistoryViewEventTargetFactory = callHistoryViewEventTargetFactory
        self.account = account
        authenticationFailureController = AuthenticationFailureController(
            accountController: accountController,
            userAgent: userAgent
        )
        accountDelegate = delegate

        super.init()

        AccountWindowRegistry.shared.register(self, key: windowKey)
        configureCallHistory()
        show(.offline, callComposerVisible: false, animated: false)
    }

    @nonobjc
    var contentView: some View {
        AccountWindowRootView(
            model: model,
            callDestinationComposer: callDestinationComposer,
            callHistoryPresenter: callHistoryPresenter,
            changeState: { [weak self] state in
                guard let self else { return }
                self.accountDelegate?.accountWindowController(
                    self,
                    didChangeAccountState: state
                )
            },
            submitAuthenticationFailure: { [weak self] authenticationFailure in
                self?.authenticationFailureController
                    .changeUsernameAndPassword(authenticationFailure)
            }
        )
        .navigationTitle(accountDescription)
    }

    func showAvailableState() {
        show(.available, callComposerVisible: true, animated: true)
    }

    func showUnavailableState() {
        show(.unavailable, callComposerVisible: true, animated: true)
    }

    func showOfflineState() {
        show(.offline, callComposerVisible: false, animated: true)
    }

    func showConnectingState() {
        withAnimation(.easeInOut(duration: 0.15)) {
            model.state = .connecting
        }
    }

    func showAuthenticationFailure() {
        guard model.authenticationFailure == nil else { return }
        model.authenticationFailure = authenticationFailureController.makeModel()
    }

    func dismissAuthenticationFailure() {
        model.authenticationFailure = nil
    }

    @objc(showRegistrarConnectionErrorWithRegistrar:error:)
    func showRegistrarConnectionError(
        registrar: String,
        error: String?
    ) {
        model.registrarConnectionError = RegistrarConnectionError(
            registrar: registrar,
            details: error
        )
    }

    func makeCallToDestination(_ destination: String) {
        callDestinationComposer.makeCallToDestination(destination)
    }

    func showWindow() {
        AccountWindowSceneController.shared.show(key: windowKey)
    }

    func showWindowWithoutMakingKey() {
        showWindow()
    }

    func hideWindow() {
        AccountWindowSceneController.shared.hide(key: windowKey)
    }

    private func configureCallHistory() {
        callHistoryViewEventTargetFactory.make(
            account: account,
            view: callHistoryPresenter
        ) { [weak self] target in
            guard let self else { return }
            self.callHistoryViewEventTarget = target
            self.callHistoryPresenter.target = target
        }
    }

    private func show(
        _ state: AccountWindowDisplayState,
        callComposerVisible: Bool,
        animated: Bool
    ) {
        let update = {
            self.model.state = state
            self.model.showsCallComposer = callComposerVisible
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.15), update)
        } else {
            update()
        }

        if callComposerVisible {
            callDestinationComposer.focus()
        }
    }
}

@MainActor
private final class AccountWindowRegistry {
    static let shared = AccountWindowRegistry()

    private final class WeakController {
        weak var value: AccountWindowController?

        init(_ value: AccountWindowController) {
            self.value = value
        }
    }

    private var controllers: [String: WeakController] = [:]

    func register(_ controller: AccountWindowController, key: String) {
        controllers[key] = WeakController(controller)
    }

    func controller(for key: String) -> AccountWindowController? {
        guard let controller = controllers[key]?.value else {
            controllers[key] = nil
            return nil
        }
        return controller
    }
}

private struct AccountWindowsScene: Scene {
    var body: some Scene {
        WindowGroup(
            NSLocalizedString(
                "Account",
                comment: "Account window scene title."
            ),
            id: AccountWindowSceneController.sceneID,
            for: String.self
        ) { key in
            if let key = key.wrappedValue,
               let controller = AccountWindowRegistry.shared.controller(for: key) {
                controller.contentView
            } else {
                EmptyView()
            }
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

@MainActor
private final class AccountWindowSceneController {
    static let shared = AccountWindowSceneController()
    static let sceneID = "telephone-account"

    private let representation = NSHostingSceneRepresentation {
        AccountWindowsScene()
    }
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        NSApplication.shared.addSceneRepresentation(representation)
    }

    func show(key: String) {
        representation.environment.openWindow(
            id: Self.sceneID,
            value: key
        )
    }

    func hide(key: String) {
        representation.environment.dismissWindow(
            id: Self.sceneID,
            value: key
        )
    }
}
