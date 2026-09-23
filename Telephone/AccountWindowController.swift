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
    private let activeAccountViewController: ActiveAccountViewController
    private let callHistoryViewController: CallHistoryViewController
    private let callHistoryViewEventTargetFactory: AsyncCallHistoryViewEventTargetFactory
    private let account: Account
    private weak var accountDelegate: AccountWindowControllerDelegate?
    private let model = AccountWindowModel()

    private var callHistoryViewEventTarget: CallHistoryViewEventTarget?

    var canMakeCalls: Bool {
        model.showsCallComposer
    }

    @objc(initWithAccountDescription:SIPAddress:accountController:callHistoryViewEventTargetFactory:account:delegate:)
    init(
        accountDescription: String,
        sipAddress: String,
        accountController: AccountController,
        callHistoryViewEventTargetFactory: AsyncCallHistoryViewEventTargetFactory,
        account: Account,
        delegate: AccountWindowControllerDelegate
    ) {
        activeAccountViewController = ActiveAccountViewController(
            accountController: accountController
        )
        callHistoryViewController = CallHistoryViewController()
        self.callHistoryViewEventTargetFactory = callHistoryViewEventTargetFactory
        self.account = account
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
            activeAccountViewController: activeAccountViewController,
            callHistoryViewController: callHistoryViewController,
            changeState: { [weak self] state in
                guard let self else { return }
                self.accountDelegate?.accountWindowController(
                    self,
                    didChangeAccountState: state
                )
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

    func makeCallToDestination(_ destination: String) {
        activeAccountViewController.makeCallToDestination(destination)
    }

    func showAlert(_ alert: NSAlert) {
        guard let window else { return }
        alert.beginSheetModal(for: window)
    }

    func beginSheet(_ sheet: NSWindow) {
        window?.beginSheet(sheet)
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
        callHistoryViewController.focusCallHistorySearch(sender)
    }

    @IBAction func makeCall(_ sender: Any?) {
        callHistoryViewController.makeCall(sender)
    }

    @IBAction func copy(_ sender: Any?) {
        callHistoryViewController.copy(sender)
    }

    @IBAction func delete(_ sender: Any?) {
        callHistoryViewController.delete(sender)
    }

    @IBAction func deleteAll(_ sender: Any?) {
        callHistoryViewController.deleteAll(sender)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(focusCallHistorySearch(_:)),
             #selector(makeCall(_:)),
             #selector(copy(_:)),
             #selector(delete(_:)),
             #selector(deleteAll(_:)):
            return callHistoryViewController.validateMenuItem(item)
        default:
            return true
        }
    }

    private func configureCallHistory() {
        callHistoryViewEventTargetFactory.make(
            account: account,
            view: callHistoryViewController
        ) { [weak self] target in
            guard let self else { return }
            self.callHistoryViewEventTarget = target
            self.callHistoryViewController.target = target
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
            activeAccountViewController.focusCallDestination()
        }
    }
}
