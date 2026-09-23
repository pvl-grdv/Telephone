//
//  AccountSetupController.swift
//  Telephone
//

import AppKit
import SwiftUI

@MainActor
@objcMembers
final class AccountSetupController: NSWindowController, NSWindowDelegate {
    private let model = AccountSetupModel()
    private var isStandalonePresentation = false
    private var didSubmit = false

    override init(window: NSWindow?) {
        let setupWindow = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        setupWindow.title = NSLocalizedString(
            "Account Setup",
            comment: "Account setup window title."
        )
        setupWindow.isReleasedWhenClosed = false

        super.init(window: setupWindow)

        let contentController = NSHostingController(
            rootView: AccountSetupView(
                model: model,
                submit: { [weak self] in
                    self?.submit()
                },
                cancel: { [weak self] in
                    self?.closePresentedWindow()
                }
            )
        )
        setupWindow.contentViewController = contentController
        setupWindow.setContentSize(contentController.view.fittingSize)
        setupWindow.delegate = self
    }

    convenience init() {
        self.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    class func didAddAccountNotificationName() -> String {
        accountSetupDidAddNotificationName.rawValue
    }

    func prepare() {
        model.reset()
    }

    func presentAsSheet(from parent: NSWindow) {
        prepare()
        isStandalonePresentation = false
        didSubmit = false

        guard let window else { return }
        parent.beginSheet(window)
    }

    func showCentered() {
        prepare()
        isStandalonePresentation = true
        didSubmit = false

        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func submit() {
        guard model.saveAccount(notificationObject: self) else {
            return
        }

        didSubmit = true
        closePresentedWindow()
    }

    private func closePresentedWindow() {
        guard let window else { return }

        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.performClose(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard isStandalonePresentation else { return }

        isStandalonePresentation = false
        if !didSubmit {
            NSApp.terminate(self)
        }
    }
}
