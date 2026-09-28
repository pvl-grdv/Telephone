//
//  MacApplicationDelegate.swift
//  Telephone
//
//  Thin AppKit bridge for the SwiftUI application lifecycle.
//

import AppKit
import UserNotifications

@MainActor
final class MacApplicationDelegate:
    NSObject,
    NSApplicationDelegate,
    @preconcurrency UNUserNotificationCenterDelegate
{
    let coordinator = ApplicationCoordinator()

    func applicationWillFinishLaunching(
        _ notification: Notification
    ) {
        coordinator.applicationWillFinishLaunching()
    }

    func application(
        _ application: NSApplication,
        open urls: [URL]
    ) {
        coordinator.open(urls: urls)
    }

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        coordinator.applicationDidFinishLaunching(
            notificationDelegate: self
        )
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        coordinator.handleReopen(hasVisibleWindows: flag)
    }

    func applicationDidBecomeActive(
        _ notification: Notification
    ) {
        coordinator.applicationDidBecomeActive()
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        switch coordinator.terminationDecision() {
        case .terminateNow:
            .terminateNow
        case .terminateLater:
            .terminateLater
        case .cancel:
            .terminateCancel
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await coordinator.handleUserNotificationResponse(
            response,
            center: center
        )
    }
}
