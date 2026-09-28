//
//  MacSystemIntegration.swift
//  Telephone
//

import AppKit
import SwiftUI

@MainActor
enum MacApplication {
    static var isActive: Bool {
        NSApplication.shared.isActive
    }

    static var coordinator: ApplicationCoordinator? {
        (NSApplication.shared.delegate as? MacApplicationDelegate)?.coordinator
    }

    static var applicationIcon: Image {
        Image(nsImage: NSApplication.shared.applicationIconImage)
    }

    static func activate() {
        NSApplication.shared.activate()
    }

    static func setDockBadgeLabel(_ value: String) {
        NSApplication.shared.dockTile.badgeLabel = value
    }

    static func replyToTermination(_ shouldTerminate: Bool) {
        NSApplication.shared.reply(
            toApplicationShouldTerminate: shouldTerminate
        )
    }

    static func terminate() {
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
final class MacWorkspaceEventSource {
    private var observations: [NotificationObservation] = []

    init(
        willSleep: @escaping @MainActor @Sendable () -> Void,
        didWake: @escaping @MainActor @Sendable () -> Void,
        sessionDidResignActive:
            @escaping @MainActor @Sendable () -> Void,
        sessionDidBecomeActive:
            @escaping @MainActor @Sendable () -> Void
    ) {
        let workspace = NSWorkspace.shared
        let center = workspace.notificationCenter

        observations = [
            observe(
                center,
                name: NSWorkspace.willSleepNotification,
                object: workspace,
                action: willSleep
            ),
            observe(
                center,
                name: NSWorkspace.didWakeNotification,
                object: workspace,
                action: didWake
            ),
            observe(
                center,
                name: NSWorkspace.sessionDidResignActiveNotification,
                object: workspace,
                action: sessionDidResignActive
            ),
            observe(
                center,
                name: NSWorkspace.sessionDidBecomeActiveNotification,
                object: workspace,
                action: sessionDidBecomeActive
            ),
        ]
    }

    private func observe(
        _ center: NotificationCenter,
        name: Notification.Name,
        object: AnyObject,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> NotificationObservation {
        NotificationObservation(
            center: center,
            name: name,
            object: object
        ) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }
    }
}

@MainActor
final class MacClipboard: Clipboard {
    static let shared = MacClipboard()

    private init() {}

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([text as NSString])
    }
}

@MainActor
struct MacFileBrowser: FileBrowser {
    func showFile(at url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

@MainActor
struct MacWebBrowser: WebBrowser {
    func showPage(at url: URL) {
        if !NSWorkspace.shared.open(url) {
            Log.systemIntegration.error(
                "Could not open URL \(url.absoluteString, privacy: .private)"
            )
        }
    }
}

@MainActor
enum MacSystem {
    static func makeWorkspaceSleepStatus() -> WorkspaceSleepStatus {
        let workspace = NSWorkspace.shared
        return WorkspaceSleepStatus(
            center: workspace.notificationCenter,
            willSleepNotification: NSWorkspace.willSleepNotification,
            didWakeNotification: NSWorkspace.didWakeNotification,
            workspace: workspace
        )
    }

    static func makeUserAttentionRequest(
        center: NotificationCenter
    ) -> ApplicationUserAttentionRequest {
        let application = NSApplication.shared
        return ApplicationUserAttentionRequest(
            center: center,
            didBecomeActiveNotification:
                NSApplication.didBecomeActiveNotification,
            application: application,
            isActive: { application.isActive },
            requestAttention: {
                application.requestUserAttention(.criticalRequest)
            },
            cancelAttention: {
                application.cancelUserAttentionRequest($0)
            }
        )
    }

    static var fileBrowser: FileBrowser {
        MacFileBrowser()
    }

    static var webBrowser: WebBrowser {
        MacWebBrowser()
    }

    static var clipboard: Clipboard {
        MacClipboard.shared
    }
}
