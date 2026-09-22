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

    var assetName: String? {
        switch self {
        case .offline:
            "offline-state"
        case .available:
            "available-state"
        case .unavailable:
            "unavailable-state"
        case .connecting:
            nil
        }
    }
}

@MainActor
@Observable
private final class AccountWindowModel {
    var state: AccountWindowDisplayState = .offline
}

@MainActor
@objcMembers
final class AccountWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static let stateItemIdentifier = NSToolbarItem.Identifier("TelephoneAccountState")

    private let accountViewController: AccountViewController
    private weak var accountDelegate: AccountWindowControllerDelegate?
    private let model = AccountWindowModel()

    var canMakeCalls: Bool {
        accountViewController.canMakeCalls
    }

    @objc(initWithAccountDescription:SIPAddress:accountViewController:delegate:)
    init(
        accountDescription: String,
        sipAddress: String,
        accountViewController: AccountViewController,
        delegate: AccountWindowControllerDelegate
    ) {
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
        toolbar.showsBaselineSeparator = false
        toolbar.delegate = self
        window.toolbar = toolbar

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

    private func show(
        _ state: AccountWindowDisplayState,
        callComposerVisible: Bool,
        animated: Bool
    ) {
        model.state = state
        accountViewController.setCallComposerVisible(
            callComposerVisible,
            animated: animated
        )
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

        let hostingView = NSHostingView(
            rootView: AccountStateToolbarView(
                model: model,
                changeState: { [weak self] state in
                    guard let self else { return }
                    self.accountDelegate?.accountWindowController(
                        self,
                        didChangeAccountState: state
                    )
                }
            )
        )
        hostingView.frame.size = hostingView.fittingSize
        item.view = hostingView
        return item
    }
}

private struct AccountStateToolbarView: View {
    @Bindable var model: AccountWindowModel

    let changeState: (AccountWindowControllerAccountState) -> Void

    var body: some View {
        Menu {
            Button {
                changeState(.available)
            } label: {
                Label(
                    NSLocalizedString(
                        "Available",
                        comment: "Account registration Available menu item."
                    ),
                    image: "available-state"
                )
            }

            Button {
                changeState(.unavailable)
            } label: {
                Label(
                    NSLocalizedString(
                        "Unavailable",
                        comment: "Account registration Unavailable menu item."
                    ),
                    image: "unavailable-state"
                )
            }

            Divider()

            Button {
                changeState(.offline)
            } label: {
                Label(
                    NSLocalizedString(
                        "Offline",
                        comment: "Account registration Offline menu item."
                    ),
                    image: "offline-state"
                )
            }
        } label: {
            HStack(spacing: 6) {
                AccountStateIndicator(state: model.state)

                Text(model.state.title)
                    .lineLimit(1)
                    .frame(minWidth: 78, alignment: .leading)
            }
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .fixedSize()
        .help(
            NSLocalizedString(
                "Account State",
                comment: "Account state toolbar item."
            )
        )
        .accessibilityLabel(
            NSLocalizedString(
                "Account State",
                comment: "Account state toolbar item."
            )
        )
        .accessibilityValue(model.state.title)
    }
}

private struct AccountStateIndicator: View {
    let state: AccountWindowDisplayState

    @ViewBuilder
    var body: some View {
        if state == .connecting {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 12, height: 12)
        } else if let assetName = state.assetName {
            Image(assetName)
                .resizable()
                .interpolation(.high)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
        }
    }
}
