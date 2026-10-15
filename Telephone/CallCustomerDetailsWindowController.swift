//
//  CallCustomerDetailsWindowController.swift
//  Telephone
//

import AppKit
import SwiftUI

/// A nonmodal CRM browser for one live call. Call controls stay in the
/// independent call window; the normal macOS titlebar closes this window.
@MainActor
final class CallCustomerDetailsWindowController: NSWindowController, NSWindowDelegate {
    private let crmKeyLookupModel: CRMKeyLookupModel

    init(model: CallWindowModel, crmKeyLookupModel: CRMKeyLookupModel) {
        self.crmKeyLookupModel = crmKeyLookupModel
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = NSLocalizedString("Client details", comment: "Live client details window title.")
        window.contentMinSize = NSSize(width: 660, height: 470)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: CallCustomerDetailsView(model: model, crmKeyLookupModel: crmKeyLookupModel)
        )
        window.center()
        window.setFrameAutosaveName("Telephone.LiveClientDetails")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        showWindow(nil)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the browser must not cancel a dispatched CRM write.
        crmKeyLookupModel.pendingPhoneLink = nil
    }
}
