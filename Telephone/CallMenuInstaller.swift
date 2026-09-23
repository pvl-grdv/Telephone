//
//  CallMenuInstaller.swift
//  Telephone
//

import AppKit

@MainActor
@objcMembers
final class CallMenuInstaller: NSObject, NSMenuItemValidation {
    private let defaults = UserDefaults.standard

    func install() {
        installCallMenu()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(toggleKeepCallWindowOnTop(_:)) else {
            return true
        }

        menuItem.state = defaults.bool(
            forKey: UserDefaultsKeys.keepCallWindowOnTop
        ) ? .on : .off
        return true
    }

    @IBAction
    private func toggleKeepCallWindowOnTop(_ sender: Any?) {
        let key = UserDefaultsKeys.keepCallWindowOnTop
        defaults.set(!defaults.bool(forKey: key), forKey: key)
    }

    private func installCallMenu() {
        guard
            let mainMenu = NSApp.mainMenu,
            !mainMenu.items.contains(where: { $0.submenu?.identifier?.rawValue == "TelephoneCallMenu" })
        else {
            return
        }

        let callMenu = NSMenu(
            title: NSLocalizedString(
                "Call",
                comment: "Call menu title."
            )
        )
        callMenu.identifier = NSUserInterfaceItemIdentifier("TelephoneCallMenu")

        callMenu.addItem(
            responderItem(
                title: NSLocalizedString("Mute", comment: "Mute. Call menu item."),
                selector: Selector(("toggleMicrophoneMute:")),
                keyEquivalent: "m",
                modifiers: [.command, .shift]
            )
        )
        callMenu.addItem(
            responderItem(
                title: NSLocalizedString("Hold", comment: "Hold. Call menu item."),
                selector: Selector(("toggleCallHold:"))
            )
        )
        callMenu.addItem(
            responderItem(
                title: NSLocalizedString("Transfer", comment: "Transfer. Call menu item."),
                selector: Selector(("showCallTransferSheet:"))
            )
        )
        callMenu.addItem(
            responderItem(
                title: NSLocalizedString("Call Back", comment: "Call back menu item."),
                selector: Selector(("redial:")),
                keyEquivalent: "r",
                modifiers: [.command]
            )
        )

        callMenu.addItem(.separator())

        callMenu.addItem(
            responderItem(
                title: NSLocalizedString("Answer", comment: "Call answer menu item."),
                selector: Selector(("acceptCall:")),
                keyEquivalent: "\r",
                modifiers: []
            )
        )
        callMenu.addItem(
            responderItem(
                title: NSLocalizedString("End Call", comment: "End call menu item."),
                selector: Selector(("hangUpCall:")),
                keyEquivalent: ".",
                modifiers: [.command]
            )
        )

        callMenu.addItem(.separator())

        let keepOnTop = NSMenuItem(
            title: NSLocalizedString(
                "Keep on Top",
                comment: "Keep call window on top menu item."
            ),
            action: #selector(toggleKeepCallWindowOnTop(_:)),
            keyEquivalent: ""
        )
        keepOnTop.target = self
        callMenu.addItem(keepOnTop)

        let rootItem = NSMenuItem(
            title: callMenu.title,
            action: nil,
            keyEquivalent: ""
        )
        rootItem.submenu = callMenu

        if let windowMenu = NSApp.windowsMenu,
           let windowIndex = mainMenu.items.firstIndex(where: { $0.submenu === windowMenu }) {
            mainMenu.insertItem(rootItem, at: windowIndex)
        } else if let helpMenu = NSApp.helpMenu,
                  let helpIndex = mainMenu.items.firstIndex(where: { $0.submenu === helpMenu }) {
            mainMenu.insertItem(rootItem, at: helpIndex)
        } else {
            mainMenu.addItem(rootItem)
        }
    }

    private func responderItem(
        title: String,
        selector: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: selector,
            keyEquivalent: keyEquivalent
        )
        item.target = nil
        item.keyEquivalentModifierMask = modifiers
        return item
    }


}
