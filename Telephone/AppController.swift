//
//  AppController.swift
//  Telephone
//
//  Application lifecycle and top-level orchestration.
//

import AppKit
import Foundation
import UserNotifications
import UseCases

@MainActor
@objc(AppController)
@objcMembers
final class AppController:
    NSObject,
    NSApplicationDelegate,
    AKSIPUserAgentDelegate,
    PreferencesControllerDelegate,
    @preconcurrency UNUserNotificationCenterDelegate,
    NameServersChangeEventTarget
{
    private var compositionRoot: CompositionRoot!
    private var accountsCommandModel: AccountsCommandModel!

    private lazy var accountSetupPresentationController =
        AccountSetupPresentationController()
    private lazy var applicationDialogController =
        ApplicationDialogController()
    private let networkReachability =
        AKNetworkReachability.networkReachability()

    private var shouldRegisterAllAccounts = false
    private var shouldRestartUserAgentASAP = false
    private var terminating = false
    private var terminationConfirmed = false
    private var shouldPresentUserAgentLaunchError = false
    private var finishedLaunching = false
    private var destinationToCall = ""
    private var userSessionActive = true

    private var restartTask: Task<Void, Never>?
    private var networkPathTask: Task<Void, Never>?

    private var userAgent: AKSIPUserAgent {
        compositionRoot.userAgent
    }

    private var accountControllers: AccountControllers {
        compositionRoot.accountControllers
    }

    private var preferencesController: PreferencesController {
        compositionRoot.preferencesController
    }

    private var userAgentStart: any UseCase {
        compositionRoot.userAgentStart
    }

    private var nameServers: NameServers {
        compositionRoot.nameServers
    }

    override init() {
        super.init()

        compositionRoot = CompositionRoot(
            preferencesControllerDelegate: self,
            nameServersChangeEventTarget: self
        )
        userAgent.delegate = self
        accountsCommandModel = AccountsCommandModel(
            controllers: accountControllers
        )

        observeApplicationEvents()
    }

    isolated deinit {
        restartTask?.cancel()
        networkPathTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func copySettings() {
        compositionRoot.helpMenuActionTarget.copySettings()
    }

    func showLogFile() {
        compositionRoot.helpMenuActionTarget.showLogFile()
    }

    func openHomepage() {
        compositionRoot.helpMenuActionTarget.openHomepage()
    }

    func openFAQ() {
        compositionRoot.helpMenuActionTarget.openFAQ()
    }

    func accountsCommandModelForSwiftUI() -> AccountsCommandModel {
        accountsCommandModel
    }

    func showPreferencesForSwiftUI() {
        preferencesController.showWindowCentered()
    }

#if DEBUG
    func showPreferencesForUITesting() {
        preferencesController.showWindowForUITesting()
    }

    func showAccountSetupForUITesting() {
        accountSetupPresentationController.showFirstRun()
    }
#endif

    func makeCallFromAppIntent(destination: String) -> Bool {
        guard finishedLaunching, canMakeCall else {
            return false
        }

        let sanitized = SanitizedCallDestination(destination)
        accountControllers.enabled.first?.makeCall(to: sanitized)
        return true
    }

    func setAccountAvailabilityFromAppIntent(
        uuid: String,
        state: Int
    ) -> Bool {
        for controller in accountControllers.enabled
        where controller.account.uuid == uuid {
            return controller.changeAccountState(rawValue: state)
        }
        return false
    }

    func updateDockTileBadgeLabel() {
        let count = accountControllers.unhandledIncomingCallsCount()
        NSApp.dockTile.badgeLabel =
            count == 0 ? "" : String(count)
    }

    // MARK: - NSApplicationDelegate

    func applicationWillFinishLaunching(
        _ notification: Notification
    ) {
        UserDefaults.standard.set(
            false,
            forKey: "NSFullScreenMenuItemEverywhere"
        )
    }

    func application(
        _ application: NSApplication,
        open urls: [URL]
    ) {
        guard
            let url = urls.first,
            let destination = SanitizedCallDestination(url: url)
        else {
            if let url = urls.first {
                NSLog("Ignoring unsupported call URL: %@", url as NSURL)
            }
            return
        }

        makeCallOrRememberDestination(destination.value)
    }

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        compositionRoot.defaultAppSettings.register()
        compositionRoot.settingsMigration.execute()

        if TelephoneUITestSupport.handleLaunch(appController: self) {
            finishedLaunching = true
            return
        }

        configureUserAgent()
        configureUserNotifications()
        NSApp.servicesProvider = self

        let accounts =
            UserDefaults.standard.array(
                forKey: UserDefaultsKeys.accounts
            ) as? [[String: Any]] ?? []

        guard !accounts.isEmpty else {
            accountSetupPresentationController.showFirstRun()
            return
        }

        for account in accounts {
            let controller = accountController(
                with: account
            )
            accountControllers.add(controller)

            if controller.enabled {
                controller.showWindow()
            }
        }

        accountControllers.updateCallsShouldDisplayAccountInfo()
        accountsCommandModel.update()
        finishedLaunching = true

        if networkReachability.isReachable {
            shouldPresentUserAgentLaunchError = true
            accountControllers.registerAllAccounts()
        }

        makeCallAfterLaunchIfNeeded()
        compositionRoot.orphanLogFileRemoval.execute()
        showAccountPreferencesIfNeeded()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if userAgent.hasUnansweredIncomingCalls {
            accountControllers.showIncomingCallWindows()
        } else if
            !flag,
            let controller = accountControllers.enabled.first
        {
            controller.showWindow()
        }

        return true
    }

    func applicationDidBecomeActive(
        _ notification: Notification
    ) {
        UNUserNotificationCenter.current()
            .removeAllDeliveredNotifications()
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        if
            accountControllers.haveActiveCallControllers(),
            !terminationConfirmed
        {
            applicationDialogController.showQuitConfirmation()
            return .terminateCancel
        }

        if userAgent.isStarted {
            terminating = true
            stopUserAgent()
            return .terminateLater
        }

        return .terminateNow
    }

    // MARK: - AKSIPUserAgentDelegate

    func sipUserAgentShouldAdd(
        _ account: AKSIPAccount
    ) -> Bool {
        if userAgent.isStarted {
            return true
        }

        if userAgent.state.rawValue == 0 {
            userAgentStart.execute()
        }
        return false
    }

    func sipUserAgentDidFinishStarting(
        _ notification: Notification
    ) {
        if userAgent.isStarted {
            if shouldRegisterAllAccounts {
                accountControllers.registerAllAccounts()
            }

            shouldRegisterAllAccounts = false
            shouldRestartUserAgentASAP = false
        } else {
            NSLog(
                "Could not start SIP user agent. Check network and STUN settings."
            )

            shouldRegisterAllAccounts = false

            if !shouldPresentUserAgentLaunchError {
                for controller in accountControllers.enabled
                where controller.shouldPresentRegistrationError {
                    shouldPresentUserAgentLaunchError = true
                    controller.resetRegistrationIntent()
                }
            }

            if
                shouldPresentUserAgentLaunchError,
                !applicationDialogController.isPresenting
            {
                applicationDialogController
                    .showSIPUserAgentLaunchError()
            }
        }

        shouldPresentUserAgentLaunchError = false
    }

    func sipUserAgentDidFinishStopping(
        _ notification: Notification
    ) {
        if terminating {
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }

        guard shouldRegisterAllAccounts else {
            return
        }

        if accountControllers.enabled.isEmpty {
            shouldRegisterAllAccounts = false
        } else {
            userAgentStart.execute()
        }
    }

    func sipUserAgentDidDetectNAT(
        _ notification: Notification
    ) {
        guard
            userAgent.detectedNATType == PJ_STUN_NAT_TYPE_BLOCKED
        else {
            return
        }

        applicationDialogController.showSTUNCommunicationError()
    }

    // MARK: - PreferencesControllerDelegate

    @objc(preferencesControllerDidRemoveAccount:)
    func preferencesControllerDidRemoveAccount(
        _ notification: Notification
    ) {
        guard
            let index = index(
                in: notification.userInfo,
                key: "AccountIndex"
            ),
            accountControllers.all.indices.contains(index)
        else {
            return
        }

        let controller = accountControllers[index]
        if controller.enabled {
            controller.removeAccountFromUserAgent()
        }

        accountControllers.remove(at: index)
        accountControllers.updateCallsShouldDisplayAccountInfo()
        accountsCommandModel.update()
    }

    @objc(preferencesControllerDidChangeAccountEnabled:)
    func preferencesControllerDidChangeAccountEnabled(
        _ notification: Notification
    ) {
        guard
            let index = index(
                in: notification.userInfo,
                key: "AccountIndex"
            ),
            let stored =
                UserDefaults.standard.array(
                    forKey: UserDefaultsKeys.accounts
                ) as? [[String: Any]],
            stored.indices.contains(index)
        else {
            return
        }

        let account = stored[index]

        if boolValue(account[UserDefaultsKeys.accountEnabled]) {
            let controller = accountController(with: account)
            controller.accountUnavailable = false
            accountControllers[index] = controller
            controller.showWindowWithoutMakingKey()
            controller.registerAccount()
        } else if accountControllers.all.indices.contains(index) {
            accountControllers[index].disableAccount()
        }

        accountControllers.updateCallsShouldDisplayAccountInfo()
        accountsCommandModel.update()
    }

    @objc(preferencesControllerDidSwapAccounts:)
    func preferencesControllerDidSwapAccounts(
        _ notification: Notification
    ) {
        guard
            let source = index(
                in: notification.userInfo,
                key: "SourceIndex"
            ),
            let destination = index(
                in: notification.userInfo,
                key: "DestinationIndex"
            ),
            source != destination,
            accountControllers.all.indices.contains(source)
        else {
            return
        }

        let controller = accountControllers[source]
        accountControllers.insert(controller, at: destination)

        if source < destination {
            accountControllers.remove(at: source)
        } else {
            accountControllers.remove(at: source + 1)
        }

        accountsCommandModel.update()
    }

    @objc(preferencesControllerDidChangeNetworkSettings:)
    func preferencesControllerDidChangeNetworkSettings(
        _ notification: Notification
    ) {
        applyNetworkSettings()

        if userAgent.isStarted {
            shouldPresentUserAgentLaunchError = true
            restartUserAgent()
        }
    }

    // MARK: - User notifications

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier

        guard let controller =
            accountControllers.callController(
                byIdentifier: identifier
            )
        else {
            return
        }

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            controller.showWindow(self)
            center.removeDeliveredNotifications(
                withIdentifiers: [identifier]
            )
        case "answer":
            controller.acceptCall()
        case "decline":
            controller.hangUpCall()
        default:
            break
        }
    }

    // MARK: - NameServersChangeEventTarget

    func nameServersDidChange(_ nameServers: NameServers) {
        let servers = nameServers.all

        guard
            UserDefaults.standard.bool(
                forKey: UserDefaultsKeys.useDNSSRV
            ),
            !servers.isEmpty,
            userAgent.nameServers != servers
        else {
            return
        }

        userAgent.nameServers = servers
        restartUserAgentAfterDelayOrMarkForRestart()
    }

    // MARK: - Services

    @objc(makeCallFromTextService:userData:error:)
    func makeCallFromTextService(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        guard
            pasteboard.canReadObject(
                forClasses: [NSString.self],
                options: [:]
            ),
            let destination =
                pasteboard.string(forType: .string)
        else {
            NSLog("Could not read call destination from pasteboard")
            return
        }

        makeCallOrRememberDestination(destination)
    }

    // MARK: - Private lifecycle

    private func observeApplicationEvents() {
        let center = NotificationCenter.default

        center.addObserver(
            self,
            selector: #selector(networkPathDidChange),
            name: AKNetworkReachability.didChangeNotification,
            object: networkReachability
        )
        center.addObserver(
            self,
            selector: #selector(accountSetupDidAddAccount),
            name: Notification.Name(
                AccountSetupPresentationController
                    .didAddAccountNotificationName()
            ),
            object: nil
        )

        for name in [
            Notification.Name.AKSIPCallCalling,
            .AKSIPCallIncoming,
            .AKSIPCallConnecting,
            .AKSIPCallDidDisconnect,
        ] {
            center.addObserver(
                self,
                selector: #selector(callStateDidChange),
                name: name,
                object: nil
            )
        }

        center.addObserver(
            self,
            selector: #selector(authenticationCredentialsDidChange),
            name: Notification.Name(
                "AKAuthenticationFailureControllerDidChangeUsernameAndPassword"
            ),
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDialogDidConfirmQuit),
            name: Notification.Name(
                ApplicationDialogController
                    .quitConfirmedNotificationName()
            ),
            object: nil
        )

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self,
            selector: #selector(workspaceWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(workspaceSessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(workspaceSessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    private func configureUserAgent() {
        applyNetworkSettings()

        let bundle = Bundle.main
        let name =
            bundle.object(
                forInfoDictionaryKey: "CFBundleName"
            ) as? String ?? "Telephone"
        let version =
            bundle.object(
                forInfoDictionaryKey:
                    "CFBundleShortVersionString"
            ) as? String ?? ""

        userAgent.userAgentString = "\(name) \(version)"
        userAgent.logFileName =
            compositionRoot.logFileURL.pathValue

        let defaults = UserDefaults.standard
        userAgent.logLevel = UInt(
            max(0, defaults.integer(
                forKey: UserDefaultsKeys.logLevel
            ))
        )
        userAgent.consoleLogLevel = UInt(
            max(0, defaults.integer(
                forKey: UserDefaultsKeys.consoleLogLevel
            ))
        )
        userAgent.detectsVoiceActivity = defaults.bool(
            forKey: UserDefaultsKeys.voiceActivityDetection
        )
        userAgent.usesICE = defaults.bool(
            forKey: UserDefaultsKeys.useICE
        )
        userAgent.usesQoS = defaults.bool(
            forKey: UserDefaultsKeys.useQoS
        )
        userAgent.usesG711Only = defaults.bool(
            forKey: UserDefaultsKeys.useG711Only
        )
        userAgent.locksCodec = defaults.bool(
            forKey: UserDefaultsKeys.lockCodec
        )
    }

    private func applyNetworkSettings() {
        let defaults = UserDefaults.standard

        userAgent.transportPort = UInt(
            max(
                0,
                defaults.integer(
                    forKey: UserDefaultsKeys.transportPort
                )
            )
        )
        userAgent.stunServerHost = defaults.string(
            forKey: UserDefaultsKeys.stunServerHost
        ) ?? ""
        userAgent.stunServerPort = UInt(
            max(
                0,
                defaults.integer(
                    forKey: UserDefaultsKeys.stunServerPort
                )
            )
        )
        userAgent.outboundProxyHost = defaults.string(
            forKey: UserDefaultsKeys.outboundProxyHost
        ) ?? ""
        userAgent.outboundProxyPort = UInt(
            max(
                0,
                defaults.integer(
                    forKey: UserDefaultsKeys.outboundProxyPort
                )
            )
        )

        userAgent.nameServers =
            defaults.bool(forKey: UserDefaultsKeys.useDNSSRV)
                ? nameServers.all
                : []
    }

    private func configureUserNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let answer = UNNotificationAction(
            identifier: "answer",
            title: NSLocalizedString(
                "Answer",
                comment: "Call answer button."
            ),
            options: [.foreground]
        )
        let decline = UNNotificationAction(
            identifier: "decline",
            title: NSLocalizedString(
                "Decline",
                comment: "Call decline button."
            ),
            options: [.destructive]
        )
        let incomingCall = UNNotificationCategory(
            identifier: "incoming-call",
            actions: [answer, decline],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([incomingCall])

        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else {
                return
            }

            do {
                _ = try await center.requestAuthorization(
                    options: [.alert]
                )
            } catch {
                NSLog(
                    "Could not request notification authorization: %@",
                    error.localizedDescription
                )
            }
        }
    }

    private func accountController(
        with dictionary: [String: Any]
    ) -> AccountController {
        let account = AKSIPAccount(
            dictionary: Dictionary(
                uniqueKeysWithValues: dictionary.map {
                    (AnyHashable($0.key), $0.value)
                }
            ),
            parser: userAgent.parser
        )

        var description =
            dictionary[AKSIPAccountKeys.desc] as? String ?? ""
        if description.isEmpty {
            description = account.sipAddress
        }

        let controller = AccountController(
            sipAccount: account,
            accountDescription: description,
            userAgent: userAgent,
            ringtonePlayback: compositionRoot.ringtonePlayback,
            sleepStatus: compositionRoot.workstationSleepStatus,
            incomingCallContactResolver:
                compositionRoot.incomingCallContactResolver,
            callHistoryViewEventTargetFactory:
                compositionRoot.callHistoryViewEventTargetFactory
        )

        controller.enabled = boolValue(
            dictionary[UserDefaultsKeys.accountEnabled]
        )
        controller.substitutesPlusCharacter = boolValue(
            dictionary[UserDefaultsKeys.substitutePlusCharacter]
        )
        controller.plusCharacterSubstitution =
            dictionary[
                UserDefaultsKeys.plusCharacterSubstitutionString
            ] as? String ?? ""

        return controller
    }

    private func stopUserAgent() {
        accountControllers
            .hangUpCallsAndRemoveAccountsFromUserAgent()
        userAgent.stop()
    }

    private func stopUserAgentAndWait() {
        accountControllers
            .hangUpCallsAndRemoveAccountsFromUserAgent()
        userAgent.stopAndWait()
    }

    private func restartUserAgent() {
        guard userAgent.isStarted else {
            return
        }

        shouldRegisterAllAccounts = true
        stopUserAgent()
    }

    private func restartUserAgentAfterDelayOrMarkForRestart() {
        guard !accountControllers.haveActiveCallControllers() else {
            shouldRestartUserAgentASAP = true
            return
        }

        restartTask?.cancel()
        restartTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            self?.restartUserAgent()
        }
    }

    private func showAccountPreferencesIfNeeded() {
        guard accountControllers.enabled.isEmpty else {
            return
        }

        preferencesController.showWindowCentered()
        preferencesController.showAccounts()
    }

    private func makeCallAfterLaunchIfNeeded() {
        guard !destinationToCall.isEmpty else {
            return
        }

        makeCall(to: destinationToCall)
        destinationToCall = ""
    }

    private func makeCallOrRememberDestination(
        _ destination: String
    ) {
        if finishedLaunching {
            makeCall(to: destination)
        } else {
            destinationToCall = destination
        }
    }

    private func makeCall(to destination: String) {
        guard
            canMakeCall,
            let controller = accountControllers.enabled.first
        else {
            return
        }

        controller.makeCall(
            to: SanitizedCallDestination(destination)
        )
    }

    private var canMakeCall: Bool {
        !applicationDialogController.isPresenting
            && !accountControllers.enabled.isEmpty
    }

    // MARK: - Event handlers

    @objc
    private func accountSetupDidAddAccount(
        _ notification: Notification
    ) {
        guard let userInfo = notification.userInfo else {
            return
        }

        let dictionary = userInfo.reduce(into: [String: Any]()) {
            result, item in
            if let key = item.key as? String {
                result[key] = item.value
            }
        }

        let isFirstLaunch = !finishedLaunching
        let controller = accountController(
            with: dictionary
        )

        accountControllers.add(controller)
        accountControllers.updateCallsShouldDisplayAccountInfo()
        accountsCommandModel.update()
        controller.showWindowWithoutMakingKey()

        if isFirstLaunch {
            finishedLaunching = true

            if networkReachability.isReachable {
                shouldPresentUserAgentLaunchError = true
                accountControllers.registerAllAccounts()
            }

            makeCallAfterLaunchIfNeeded()
        } else if controller.enabled {
            controller.registerAccount()
        }
    }

    @objc
    private func callStateDidChange(
        _ notification: Notification
    ) {
        updateDockTileBadgeLabel()

        if
            notification.name == .AKSIPCallDidDisconnect,
            shouldRestartUserAgentASAP,
            !accountControllers.haveActiveCallControllers()
        {
            restartTask?.cancel()
            shouldRestartUserAgentASAP = false
            restartUserAgent()
        }
    }

    @objc
    private func authenticationCredentialsDidChange(
        _ notification: Notification
    ) {
        guard
            let failure =
                notification.object
                    as? AuthenticationFailureController,
            let controller = failure.accountController
        else {
            return
        }

        let index = accountControllers.index(of: controller)
        guard index != NSNotFound else {
            return
        }

        let defaults = UserDefaults.standard
        guard var accounts =
            defaults.array(
                forKey: UserDefaultsKeys.accounts
            ) as? [[String: Any]],
            accounts.indices.contains(index)
        else {
            return
        }

        accounts[index][AKSIPAccountKeys.username] =
            controller.account.username
        defaults.set(
            accounts,
            forKey: UserDefaultsKeys.accounts
        )
        preferencesController.reloadAccount(at: index)
    }

    @objc
    private func applicationDialogDidConfirmQuit(
        _ notification: Notification
    ) {
        terminationConfirmed = true
        NSApp.terminate(self)
    }

    @objc
    private func workspaceWillSleep(
        _ notification: Notification
    ) {
        networkPathTask?.cancel()

        if userAgent.isStarted {
            stopUserAgentAndWait()
        }
    }

    @objc
    private func workspaceDidWake(
        _ notification: Notification
    ) {
        if
            userSessionActive,
            networkReachability.isReachable
        {
            accountControllers.registerAllAccounts()
        }
    }

    @objc
    private func workspaceSessionDidResignActive(
        _ notification: Notification
    ) {
        networkPathTask?.cancel()
        userSessionActive = false
        accountControllers.unregisterAllAccounts()
    }

    @objc
    private func workspaceSessionDidBecomeActive(
        _ notification: Notification
    ) {
        userSessionActive = true

        if networkReachability.isReachable {
            accountControllers.registerAllAccounts()
        }
    }

    @objc
    private func networkPathDidChange(
        _ notification: Notification
    ) {
        networkPathTask?.cancel()

        guard
            networkReachability.isReachable,
            finishedLaunching,
            userSessionActive
        else {
            return
        }

        networkPathTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            self?.handleNetworkPathChange()
        }
    }

    private func handleNetworkPathChange() {
        guard
            networkReachability.isReachable,
            finishedLaunching,
            userSessionActive
        else {
            return
        }

        if userAgent.isStarted {
            userAgent.handleIPAddressChange()
        } else {
            accountControllers.registerAllAccounts()
        }
    }
}

private func boolValue(_ value: Any?) -> Bool {
    (value as? NSNumber)?.boolValue
        ?? (value as? Bool)
        ?? false
}

private func index(
    in userInfo: [AnyHashable: Any]?,
    key: String
) -> Int? {
    guard let value = userInfo?[key] else {
        return nil
    }

    if let number = value as? NSNumber {
        return number.intValue
    }
    return value as? Int
}
