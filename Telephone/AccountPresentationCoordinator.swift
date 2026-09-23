//
//  AccountPresentationCoordinator.swift
//  Telephone
//

import Foundation
import SwiftUI
import UseCases

@objc enum AccountAvailabilityState: Int {
    case offline
    case available
    case unavailable
}

@objc protocol AccountPresentationCoordinatorDelegate: AnyObject {
    func accountPresentationCoordinator(
        _ controller: AccountPresentationCoordinator,
        didChangeAccountState state: AccountAvailabilityState
    )
}

@MainActor
@objcMembers
final class AccountPresentationCoordinator: NSObject {
    private let accountDescription: String
    private let windowKey: String
    private let callDestinationComposer: CallDestinationComposer
    private let callHistoryPresenter: CallHistoryPresenter
    private let callHistoryViewEventTargetFactory: AsyncCallHistoryViewEventTargetFactory
    private let account: Account
    private let authenticationFailureController: AuthenticationFailureController
    private weak var accountDelegate: AccountPresentationCoordinatorDelegate?
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
        delegate: AccountPresentationCoordinatorDelegate
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

        AccountPresentationRegistry.shared.register(self, key: windowKey)
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
                self.accountDelegate?.accountPresentationCoordinator(
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
        .focusedSceneValue(\.callHistoryPresenter, callHistoryPresenter)
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

    func invalidate() {
        dismissAuthenticationFailure()
        callHistoryPresenter.target = nil
        callHistoryViewEventTarget = nil
        AccountPresentationRegistry.shared.unregister(key: windowKey)
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
