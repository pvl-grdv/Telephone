//
//  AccountWindowController.swift
//  Telephone
//

import AppKit
import Observation
import SwiftUI

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

private enum AccountWindowDisplayState {
    case offline
    case connecting
    case available
    case unavailable

    var title: String {
        switch self {
        case .offline:
            NSLocalizedString("Offline", comment: "Account registration Offline menu item.")
        case .connecting:
            NSLocalizedString("Connecting...", comment: "Account registration Connecting... menu item.")
        case .available:
            NSLocalizedString("Available", comment: "Account registration Available menu item.")
        case .unavailable:
            NSLocalizedString("Unavailable", comment: "Account registration Unavailable menu item.")
        }
    }

    var systemImage: String {
        switch self {
        case .offline:
            "circle.fill"
        case .connecting:
            "arrow.triangle.2.circlepath"
        case .available:
            "circle.fill"
        case .unavailable:
            "circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .available:
            .green
        case .unavailable:
            .yellow
        case .offline:
            .secondary
        case .connecting:
            .secondary
        }
    }
}

@MainActor
@Observable
private final class AccountWindowModel {
    var state: AccountWindowDisplayState = .offline
    var requestStateChange: ((AccountWindowControllerAccountState) -> Void)?
}

@MainActor
@objcMembers
final class AccountWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static let stateItemIdentifier = NSToolbarItem.Identifier("TelephoneAccountState")

    private let accountDescription: String
    private let sipAddress: String
    private let accountViewController: AccountViewController
    private weak var accountDelegate: AccountWindowControllerDelegate?
    private let model = AccountWindowModel()

    var allowsCallDestinationInput: Bool {
        accountViewController.allowsCallDestinationInput
    }

    @objc(initWithAccountDescription:SIPAddress:accountViewController:delegate:)
    init(
        accountDescription: String,
        sipAddress: String,
        accountViewController: AccountViewController,
        delegate: AccountWindowControllerDelegate
    ) {
        self.accountDescription = accountDescription
        self.sipAddress = sipAddress
        self.accountViewController = accountViewController
        self.accountDelegate = delegate

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 253),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = accountDescription
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior.insert(.fullScreenNone)
        window.contentViewController = accountViewController

        super.init(window: window)

        shouldCascadeWindows = false
        window.delegate = self
        window.setFrameAutosaveName(sipAddress)

        let toolbar = NSToolbar(identifier: "TelephoneAccountToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        toolbar.delegate = self
        window.toolbar = toolbar

        model.requestStateChange = { [weak self] state in
            guard let self else { return }
            self.accountDelegate?.accountWindowController(self, didChangeAccountState: state)
        }

        showOfflineState(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAvailableState() {
        model.state = .available
        accountViewController.showActiveState()
    }

    func showUnavailableState() {
        model.state = .unavailable
        accountViewController.showActiveState()
    }

    func showOfflineState() {
        showOfflineState(animated: true)
    }

    func showConnectingState() {
        model.state = .connecting
    }

    func makeCallToDestination(_ destination: String) {
        accountViewController.makeCallToDestination(destination)
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

    func orderWindow(_ place: NSWindow.OrderingMode, relativeTo otherWindow: Int) {
        window?.order(place, relativeTo: otherWindow)
    }

    func windowNumber() -> Int {
        window?.windowNumber ?? 0
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func showOfflineState(animated: Bool) {
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                model.state = .offline
            }
        } else {
            model.state = .offline
        }
        accountViewController.showInactiveStateAnimated(animated)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.stateItemIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.stateItemIdentifier]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.stateItemIdentifier else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = NSLocalizedString("Account State", comment: "Account state toolbar item.")
        item.paletteLabel = item.label

        let hostingView = NSHostingView(rootView: AccountStateToolbarView(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 132, height: 28)
        item.view = hostingView
        item.minSize = NSSize(width: 110, height: 28)
        item.maxSize = NSSize(width: 160, height: 28)
        return item
    }
}

private struct AccountStateToolbarView: View {
    @Bindable var model: AccountWindowModel

    var body: some View {
        Menu {
            Button {
                model.requestStateChange?(.available)
            } label: {
                Label(
                    NSLocalizedString("Available", comment: "Account registration Available menu item."),
                    systemImage: "circle.fill"
                )
            }

            Button {
                model.requestStateChange?(.unavailable)
            } label: {
                Label(
                    NSLocalizedString("Unavailable", comment: "Account registration Unavailable menu item."),
                    systemImage: "circle.fill"
                )
            }

            Divider()

            Button {
                model.requestStateChange?(.offline)
            } label: {
                Label(
                    NSLocalizedString("Offline", comment: "Account registration Offline menu item."),
                    systemImage: "circle.fill"
                )
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.state.systemImage)
                    .foregroundStyle(model.state.tint)
                    .font(.caption)

                Text(model.state.title)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
