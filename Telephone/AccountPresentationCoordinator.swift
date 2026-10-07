//
//  AccountPresentationCoordinator.swift
//  Telephone
//

import Foundation
import SwiftUI
import UseCases

enum AccountAvailabilityState: Int {
    case offline
    case available
    case unavailable
}

protocol AccountPresentationCoordinatorDelegate: AnyObject {
    func accountPresentationCoordinator(
        _ controller: AccountPresentationCoordinator,
        didChangeAccountState state: AccountAvailabilityState
    )
}

@MainActor
final class AccountPresentationCoordinator {
    private let accountDescription: String
    private let windowKey: String
    private let callDestinationComposer: CallDestinationComposer
    private let callHistoryPresenter: CallHistoryPresenter
    private let callHistoryViewEventTargetFactory: AsyncCallHistoryViewEventTargetFactory
    private let account: any CallMakingAccount
    private let authenticationFailureController: AuthenticationFailureController
    private weak var accountDelegate: AccountPresentationCoordinatorDelegate?
    private let session: AccountSession
    private let model: AccountWindowModel

    private var callHistoryViewEventTarget: CallHistoryViewEventTarget?
    private var callHistoryConfigured = false

    init(
        accountDescription: String,
        accountController: AccountController,
        userAgent: AKSIPUserAgent,
        callHistoryViewEventTargetFactory: AsyncCallHistoryViewEventTargetFactory,
        account: any CallMakingAccount,
        session: AccountSession,
        delegate: AccountPresentationCoordinatorDelegate
    ) {
        self.accountDescription = accountDescription
        windowKey = account.uuid
        callDestinationComposer = CallDestinationComposer(
            accountController: accountController
        )
        callHistoryPresenter = CallHistoryPresenter(
            crmLookupModel: CRMHistoryLookupModel(
                storage: DefaultCallHistoryCRMStorage(),
                settings: accountController.crmGatewaySettings,
                provider: accountController.crmKeyLookupProvider,
                appendRegistry: accountController.crmPhoneAppendRegistry
            ),
            accountUUID: account.uuid
        )
        self.callHistoryViewEventTargetFactory = callHistoryViewEventTargetFactory
        self.account = account
        authenticationFailureController = AuthenticationFailureController(
            accountController: accountController,
            userAgent: userAgent
        )
        accountDelegate = delegate

        self.session = session
        model = AccountWindowModel(session: session)

        AccountPresentationRegistry.shared.register(self, key: windowKey)
    }

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
        .onAppear { [weak self] in
            self?.configureCallHistoryIfNeeded()
        }
    }

    func accountStateDidChange() {
        if session.state != .connecting, session.canMakeCalls {
            callDestinationComposer.focus()
        }
    }
    func showAuthenticationFailure() {
        guard model.authenticationFailure == nil else { return }
        model.authenticationFailure = authenticationFailureController.makeModel()
    }

    func dismissAuthenticationFailure() {
        model.authenticationFailure = nil
    }

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
        SceneRouter.shared.openWindow(
            id: AccountWindowScene.id,
            value: windowKey
        )
    }

    func hideWindow() {
        SceneRouter.shared.dismissWindow(
            id: AccountWindowScene.id,
            value: windowKey
        )
    }

    func invalidate() {
        dismissAuthenticationFailure()
        callHistoryPresenter.closeCRM()
        callHistoryPresenter.target = nil
        callHistoryViewEventTarget = nil
        AccountPresentationRegistry.shared.unregister(key: windowKey)
    }

    private func configureCallHistoryIfNeeded() {
        guard !callHistoryConfigured else { return }
        callHistoryConfigured = true

        callHistoryViewEventTargetFactory.make(
            account: account,
            view: callHistoryPresenter
        ) { [weak self] target in
            guard let self else { return }
            self.callHistoryViewEventTarget = target
            self.callHistoryPresenter.target = target
        }
    }

}
