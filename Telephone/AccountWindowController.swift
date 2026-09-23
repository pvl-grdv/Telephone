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
final class AccountWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
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

    @objc(initWithAccountDescription:SIPAddress:accountController:userAgent:callHistoryViewEventTargetFactory:account:delegate:)
    init(
        accountDescription: String,
        sipAddress: String,
        accountController: AccountController,
        userAgent: AKSIPUserAgent,
        callHistoryViewEventTargetFactory: AsyncCallHistoryViewEventTargetFactory,
        account: Account,
        delegate: AccountWindowControllerDelegate
    ) {
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

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = accountDescription
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior.insert(.fullScreenNone)
        window.contentMinSize = NSSize(width: 340, height: 220)
        window.toolbarStyle = .unifiedCompact

        super.init(window: window)

        shouldCascadeWindows = false
        window.delegate = self
        window.setFrameAutosaveName(sipAddress)

        let rootView = AccountWindowRootView(
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
        window.contentViewController = NSHostingController(rootView: rootView)

        configureCallHistory()
        show(.offline, callComposerVisible: false, animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    func showWindowWithoutMakingKey() {
        window?.orderFront(nil)
    }

    func hideWindow() {
        window?.orderOut(nil)
    }

    func isWindowKey() -> Bool {
        window?.isKeyWindow ?? false
    }

    func orderWindow(
        _ place: NSWindow.OrderingMode,
        relativeTo otherWindow: Int
    ) {
        window?.order(place, relativeTo: otherWindow)
    }

    func windowNumber() -> Int {
        window?.windowNumber ?? 0
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    @IBAction func focusCallHistorySearch(_ sender: Any?) {
        callHistoryPresenter.focusSearch()
    }

    @IBAction func makeCall(_ sender: Any?) {
        callHistoryPresenter.makeCall()
    }

    @IBAction func copy(_ sender: Any?) {
        callHistoryPresenter.copySelectedAddress()
    }

    @IBAction func delete(_ sender: Any?) {
        callHistoryPresenter.delete()
    }

    @IBAction func deleteAll(_ sender: Any?) {
        callHistoryPresenter.deleteAll()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(focusCallHistorySearch(_:)):
            return true
        case #selector(makeCall(_:)),
             #selector(copy(_:)),
             #selector(delete(_:)):
            return callHistoryPresenter.hasSelection
        case #selector(deleteAll(_:)):
            return callHistoryPresenter.hasRecords
        default:
            return true
        }
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
