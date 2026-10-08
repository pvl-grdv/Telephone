//
//  CallCustomerDetailsWindowController.swift
//  Telephone
//

import AppKit
import SwiftUI

/// Owned by one call presentation, never by a transient SwiftUI editor.
/// AppKit keeps this independent window out of the call scene's keyboard scope.
@MainActor
final class CallCustomerDetailsWindowController: NSWindowController, NSWindowDelegate {
    private let crmKeyLookupModel: CRMKeyLookupModel?
    private let saveOnClose: () -> Void

    init(model: CallWindowModel, crmKeyLookupModel: CRMKeyLookupModel?,
         changed: @escaping () -> Void, reload: @escaping () -> Void,
         save: @escaping () -> Void, saveOnClose: @escaping () -> Void) {
        self.crmKeyLookupModel = crmKeyLookupModel
        self.saveOnClose = saveOnClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = NSLocalizedString("Client details", comment: "Live client details window title.")
        window.contentMinSize = NSSize(width: 660, height: 500)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: CallCustomerDetailsView(
            model: model, crmKeyLookupModel: crmKeyLookupModel,
            changed: changed, reload: reload, save: save, close: { [weak self] in self?.close() }
        ))
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
        // Dismissing an unconfirmed prompt is not approval. Keep the live
        // lookup and dispatched writes alive until the call owner ends them.
        crmKeyLookupModel?.pendingPhoneLink = nil
        saveOnClose()
    }
}
