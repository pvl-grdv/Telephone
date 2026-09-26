//
//  AccountController.swift
//  Telephone
//
//  Owns one configured SIP account and its call windows.
//

import AppKit
import Foundation
import UserNotifications
import UseCases

@MainActor
@objc(AccountController)
@objcMembers
final class AccountController:
    NSObject,
    @preconcurrency AKSIPAccountDelegate,
    @preconcurrency CallControllerDelegate,
    AccountPresentationCoordinatorDelegate
{
    let account: AKSIPAccount
    let ringtonePlayback: any RingtonePlaybackUseCase
    let accountDescription: String

    @objc(isEnabled)
    var enabled = false

    var callControllers: [CallController] = []

    var attemptingToRegisterAccount: Bool {
        get { presentation.attemptingToRegister }
        set { presentation.attemptingToRegister = newValue }
    }

    var attemptingToUnregisterAccount: Bool {
        get { presentation.attemptingToUnregister }
        set { presentation.attemptingToUnregister = newValue }
    }

    var shouldPresentRegistrationError: Bool {
        get { presentation.shouldPresentRegistrationError }
        set { presentation.shouldPresentRegistrationError = newValue }
    }

    @objc(isAccountUnavailable)
    var accountUnavailable: Bool {
        get { presentation.accountUnavailable }
        set { presentation.accountUnavailable = newValue }
    }

    var substitutesPlusCharacter = false
    var plusCharacterSubstitution = ""

    var callsShouldDisplayAccountInfo = false {
        didSet {
            for controller in callControllers {
                controller.setShowsAccountInfo(
                    callsShouldDisplayAccountInfo
                )
            }
        }
    }

    @objc(isAccountRegistered)
    var accountRegistered: Bool {
        account.isRegistered
    }

    var canMakeCalls: Bool {
        presentation.canMakeCalls
    }

    private let userAgent: AKSIPUserAgent
    private let sleepStatus: WorkspaceSleepStatus
    private let incomingCallContactResolver: IncomingCallContactResolver
    private var presentation: AccountPresentationCoordinator!

    private var reRegistrationTimer: Foundation.Timer?
    private var destinationToCall = ""

    private var accountAdded: Bool {
        account.identifier >= 0
    }

    @objc(
        initWithSIPAccount:accountDescription:userAgent:ringtonePlayback:sleepStatus:incomingCallContactResolver:callHistoryViewEventTargetFactory:
    )
    init(
        sipAccount account: AKSIPAccount,
        accountDescription: String,
        userAgent: AKSIPUserAgent,
        ringtonePlayback: any RingtonePlaybackUseCase,
        sleepStatus: WorkspaceSleepStatus,
        incomingCallContactResolver: IncomingCallContactResolver,
        callHistoryViewEventTargetFactory: AsyncCallHistoryViewEventTargetFactory
    ) {
        self.account = account
        self.accountDescription = accountDescription
        self.userAgent = userAgent
        self.ringtonePlayback = ringtonePlayback
        self.sleepStatus = sleepStatus
        self.incomingCallContactResolver = incomingCallContactResolver

        super.init()

        account.delegate = self

        presentation = AccountPresentationCoordinator(
            accountDescription: accountDescription,
            accountController: self,
            userAgent: userAgent,
            callHistoryViewEventTargetFactory:
                callHistoryViewEventTargetFactory,
            account: AccountControllerToAccountAdapter(
                controller: self
            ),
            delegate: self
        )
    }

    isolated deinit {
        for controller in callControllers {
            controller.close()
        }

        if account.delegate === self {
            account.delegate = nil
        }

        presentation?.invalidate()
    }

    override var description: String {
        "\(account) controller"
    }

    func registerAccount() {
        if !userAgent.isStarted {
            attemptingToRegisterAccount = true
        }

        setAccountRegistered(true)
    }

    func unregisterAccount() {
        if !accountAdded {
            attemptingToUnregisterAccount = true
        }

        setAccountRegistered(false)
    }

    func resetRegistrationIntent() {
        presentation.resetRegistrationIntent()
    }

    func disableAccount() {
        for controller in callControllers {
            controller.close()
        }

        removeAccountFromUserAgent()
        enabled = false
        resetRegistrationIntent()
        hideWindow()
    }

    func userAgentDidFinishStarting() {
        guard userAgent.isStarted else {
            showOfflineState()
            return
        }

        if attemptingToRegisterAccount {
            registerAccount()
        } else if attemptingToUnregisterAccount {
            unregisterAccount()
        }
    }

    func removeAccountFromUserAgent() {
        precondition(
            enabled,
            "Account controller must be enabled before removal."
        )

        invalidateReRegistrationTimer()
        showOfflineState()
        _ = userAgent.removeAccount(account)
    }

    @objc(makeCallToURI:phoneLabel:callTransferController:)
    func makeCall(
        to destinationURI: AKSIPURI,
        phoneLabel: String,
        callTransferController: CallTransferController?
    ) {
        let defaults = UserDefaults.standard
        let phoneFormatter = AKTelephoneNumberFormatter()
        phoneFormatter.splitsLastFourDigits = defaults.bool(
            forKey:
                UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits
        )

        var enteredDestination = destinationURI.user

        if !containsASCIILetter(destinationURI.user) {
            destinationURI.user =
                phoneFormatter.telephoneNumber(
                    from: destinationURI.user
                )
        }

        if substitutesPlusCharacter,
           destinationURI.user.hasPrefix("+")
        {
            destinationURI.user =
                plusCharacterSubstitution
                + destinationURI.user.dropFirst()

            if enteredDestination.hasPrefix("+") {
                enteredDestination =
                    plusCharacterSubstitution
                    + enteredDestination.dropFirst()
            }
        }

        let controller = callTransferController
            ?? CallController(
                windowNibName: "Call",
                accountController: self,
                userAgent: userAgent,
                delegate: self
            )

        controller.nameFromAddressBook = destinationURI.displayName
        controller.phoneLabelFromAddressBook = phoneLabel
        controller.enteredCallDestination = enteredDestination

        if !callControllers.contains(where: { $0 === controller }) {
            callControllers.append(controller)
        }

        configureOutgoingIdentity(
            controller: controller,
            destinationURI: destinationURI,
            enteredDestination: enteredDestination,
            formatter: phoneFormatter,
            defaults: defaults
        )

        // Never send a local Contacts display name to the remote party.
        destinationURI.displayName = ""

        if destinationURI.host.isEmpty {
            destinationURI.host = account.uri.host
        }

        controller.redialURI = destinationURI
        controller.prepareForCall()

        if phoneLabel.isEmpty {
            controller.status = NSLocalizedString(
                "calling...",
                comment: "Outgoing call in progress."
            )
        } else {
            controller.status = String(
                format: NSLocalizedString(
                    "calling %@...",
                    comment: "Outgoing call in progress."
                ),
                phoneLabel
            )
        }

        if callTransferController == nil {
            controller.showWindow(self)
        }

        account.makeCall(to: destinationURI) { [weak controller] call in
            Task { @MainActor in
                guard let controller else { return }

                if let call {
                    controller.call = call
                    controller.callActive = true
                } else {
                    controller.showEndedCallView()
                    controller.status = NSLocalizedString(
                        "Call Failed",
                        comment: "Call failed."
                    )
                }
            }
        }
    }

    @objc(makeCallToURI:phoneLabel:)
    func makeCall(
        to destinationURI: AKSIPURI,
        phoneLabel: String
    ) {
        guard accountAdded else { return }

        makeCall(
            to: destinationURI,
            phoneLabel: phoneLabel,
            callTransferController: nil
        )
    }

    @objc(makeCallToDestinationRegisteringAccountIfNeeded:)
    func makeCall(
        to destination: SanitizedCallDestination
    ) {
        if !accountAdded {
            destinationToCall = destination.value
            registerAccount()
        } else {
            makeCallToDestination(destination.value)
        }
    }

    func showWindow() {
        presentation.showWindow()
    }

    func showWindowWithoutMakingKey() {
        presentation.showWindowWithoutMakingKey()
    }

    func hideWindow() {
        presentation.hideWindow()
    }

    @objc(changeAccountStateRawValue:)
    func changeAccountState(rawValue: Int) -> Bool {
        guard
            enabled,
            let state = AccountAvailabilityState(rawValue: rawValue)
        else {
            return false
        }

        changeAccountState(state)
        return true
    }

    @objc(showRegistrarConnectionErrorSheetWithError:)
    func showRegistrarConnectionErrorSheet(error: String) {
        presentation.showRegistrarConnectionError(
            registrar: account.registrar.stringValue,
            error: error
        )
    }

    func showUnavailableState() {
        presentation.showUnavailableState()
    }

    func showConnectingState() {
        presentation.showConnectingState()
    }

    // MARK: - AccountPresentationCoordinatorDelegate

    func accountPresentationCoordinator(
        _ controller: AccountPresentationCoordinator,
        didChangeAccountState state: AccountAvailabilityState
    ) {
        changeAccountState(state)
    }

    // MARK: - AKSIPAccountDelegate

    @objc(SIPAccountRegistrationDidChange:)
    func sipAccountRegistrationDidChange(_ account: AKSIPAccount) {
        guard accountAdded else { return }

        if account.isRegistered {
            invalidateReRegistrationTimer()

            if attemptingToUnregisterAccount {
                unregisterAccount()
            } else {
                accountUnavailable = false
                showAvailableState()

                if !destinationToCall.isEmpty {
                    makeCallToSavedDestination()
                }
            }
        } else {
            showUnavailableState()
            handleRegistrationFailureIfNeeded()
        }

        attemptingToRegisterAccount = false
        attemptingToUnregisterAccount = false
        shouldPresentRegistrationError = false
    }

    @objc(SIPAccountWillRemove:)
    func sipAccountWillRemove(_ account: AKSIPAccount) {
        invalidateReRegistrationTimer()
    }

    @objc(SIPAccount:didReceiveCall:)
    func sipAccount(
        _ account: AKSIPAccount,
        didReceive call: AKSIPCall
    ) {
        if accountUnavailable {
            call.replyWithTemporarilyUnavailable()
            return
        }

        if !UserDefaults.standard.bool(
            forKey: UserDefaultsKeys.callWaiting
        ), callControllers.contains(where: { $0.callActive }) {
            call.replyWithBusyHere()
            return
        }

        presentIncoming(call)
    }

    // MARK: - CallControllerDelegate

    func callControllerWillClose(_ callController: CallController) {
        callControllers.removeAll { $0 === callController }

        (NSApp.delegate as? AppController)?
            .updateDockTileBadgeLabel()
    }

    // MARK: - Registration

    private func setAccountRegistered(_ registered: Bool) {
        invalidateReRegistrationTimer()

        if accountAdded {
            showConnectingState()
            account.isRegistered = registered
            return
        }

        let serviceName = "SIP: \(account.registrar)"
        let password = AKKeychain.password(
            forService: serviceName,
            account: account.username
        )

        showConnectingState()

        let added = userAgent.addAccount(
            account,
            withPassword: password
        )

        guard
            added,
            !account.isRegistered,
            account.registrationExpireTime == -1,
            userAgent.isStarted
        else {
            return
        }

        showUnavailableState()
        scheduleReRegistrationIfNeeded()

        if shouldPresentRegistrationError {
            showRegistrarConnectionErrorSheet(
                error: registrationErrorDescription()
            )
        }

        shouldPresentRegistrationError = false
    }

    private func handleRegistrationFailureIfNeeded() {
        if account.registrationStatus == 401,
           account.registrationErrorCode == Int(TelephonePJSIPFailedCredentialError())
        {
            presentation.showAuthenticationFailure()
            return
        }

        guard
            account.registrationStatus / 100 != 2,
            account.registrationExpireTime == -1,
            userAgent.isStarted
        else {
            return
        }

        if shouldPresentRegistrationError {
            showRegistrarConnectionErrorSheet(
                error: registrationErrorDescription()
            )
        } else {
            scheduleReRegistrationIfNeeded()
        }
    }

    private func registrationErrorDescription() -> String {
        let statusText: String?

        if Bundle.main.preferredLocalizations.first == "ru" {
            statusText = SIPResponseLocalization.localizedString(
                for: account.registrationStatus
            )
        } else {
            statusText = account.registrationStatusText
        }

        guard let statusText, !statusText.isEmpty else {
            return String(
                format: NSLocalizedString(
                    "Error %ld",
                    comment: "Error #."
                ),
                account.registrationStatus
            ) + "."
        }

        return String(
            format: NSLocalizedString(
                "The error was: “%ld %@”.",
                comment: "Error description."
            ),
            account.registrationStatus,
            statusText
        )
    }

    private func scheduleReRegistrationIfNeeded() {
        guard reRegistrationTimer == nil else { return }

        reRegistrationTimer = Foundation.Timer.scheduledTimer(
            withTimeInterval: TimeInterval(account.reregistrationTime),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.account.isRegistered = true
            }
        }
    }

    private func invalidateReRegistrationTimer() {
        reRegistrationTimer?.invalidate()
        reRegistrationTimer = nil
    }

    private func changeAccountState(
        _ state: AccountAvailabilityState
    ) {
        invalidateReRegistrationTimer()

        switch state {
        case .offline:
            accountUnavailable = false
            removeAccountFromUserAgent()

        case .available:
            accountUnavailable = false
            shouldPresentRegistrationError = true
            registerAccount()

        case .unavailable:
            if accountRegistered || !accountAdded {
                accountUnavailable = true
                shouldPresentRegistrationError = true
                unregisterAccount()
            }
        }
    }

    private func showAvailableState() {
        presentation.showAvailableState()
    }

    private func showOfflineState() {
        presentation.showOfflineState()
    }

    // MARK: - Outgoing calls

    private func configureOutgoingIdentity(
        controller: CallController,
        destinationURI: AKSIPURI,
        enteredDestination: String,
        formatter: AKTelephoneNumberFormatter,
        defaults: UserDefaults
    ) {
        if !destinationURI.host.isEmpty {
            controller.title = destinationURI.sipAddress
        } else if !containsASCIILetter(enteredDestination) {
            if isTelephoneNumber(enteredDestination),
               defaults.bool(
                    forKey: UserDefaultsKeys.formatTelephoneNumbers
               )
            {
                controller.title =
                    formatter.string(for: enteredDestination)
            } else {
                controller.title = enteredDestination
            }
        } else {
            controller.title = SIPAddress(
                user: destinationURI.user,
                host: account.uri.host
            ).stringValue
        }

        if !destinationURI.displayName.isEmpty {
            controller.displayedName = destinationURI.displayName
        } else if !destinationURI.host.isEmpty {
            controller.displayedName = destinationURI.sipAddress
        } else if isTelephoneNumber(enteredDestination),
                  defaults.bool(
                    forKey: UserDefaultsKeys.formatTelephoneNumbers
                  )
        {
            controller.displayedName =
                formatter.string(for: enteredDestination)
        } else {
            controller.displayedName = enteredDestination
        }
    }

    private func makeCallToDestination(_ destination: String) {
        presentation.makeCallToDestination(destination)
    }

    private func makeCallToSavedDestination() {
        makeCallToDestination(destinationToCall)
        destinationToCall = ""
    }

    // MARK: - Incoming calls

    private func presentIncoming(_ call: AKSIPCall) {
        let controller = CallController(
            windowNibName: "Call",
            accountController: self,
            userAgent: userAgent,
            delegate: self
        )

        controller.call = call
        controller.callActive = true
        callControllers.append(controller)

        let defaults = UserDefaults.standard
        let callSource = formattedIncomingCallSource(
            call,
            defaults: defaults
        )
        let identity = CallerIdentityPresentation.make(
            sipDisplayName: call.remoteURI.displayName,
            callSource: callSource,
            contactName: "",
            organization: "",
            label: ""
        )

        controller.displayedName = identity.primary
        controller.identityDetail = identity.detail
        controller.status = NSLocalizedString(
            "calling",
            comment: "Somebody is calling us right now."
        )
        controller.redialURI = call.remoteURI
        controller.showIncomingCallView()
        controller.showWindow(nil)

        startPlayingRingtoneOrLogError()
        call.sendRingingNotification()

        incomingCallContactResolver.resolve(
            user: call.remoteURI.user,
            host: call.remoteURI.host,
            displayName: call.remoteURI.displayName,
            domain: account.uri.host
        ) { [weak self, weak controller, weak call] contact in
            guard
                let self,
                let controller,
                let call,
                controller.callActive,
                call.isMissed,
                call.state.rawValue != 6
            else {
                return
            }

            if let contact {
                controller.nameFromAddressBook = contact.name
                controller.organizationFromAddressBook =
                    contact.organization
                controller.phoneLabelFromAddressBook = contact.label

                let source = self.formattedIncomingCallSource(
                    call,
                    defaults: defaults
                )
                let identity = CallerIdentityPresentation.make(
                    sipDisplayName: call.remoteURI.displayName,
                    callSource: source,
                    contactName: contact.name,
                    organization: contact.organization,
                    label: contact.label
                )

                controller.displayedName = identity.primary
                controller.identityDetail = identity.detail
            }

            self.deliverIncomingCallNotification(
                controller: controller,
                call: call,
                defaults: defaults
            )
        }
    }

    private func formattedIncomingCallSource(
        _ call: AKSIPCall,
        defaults: UserDefaults
    ) -> String {
        let remoteURI = call.remoteURI

        guard !remoteURI.user.isEmpty else {
            return remoteURI.host
        }

        guard isTelephoneNumber(remoteURI.user) else {
            return remoteURI.sipAddress.isEmpty
                ? remoteURI.user
                : remoteURI.sipAddress
        }

        guard defaults.bool(
            forKey: UserDefaultsKeys.formatTelephoneNumbers
        ) else {
            return remoteURI.user
        }

        let formatter = AKTelephoneNumberFormatter()
        formatter.splitsLastFourDigits = defaults.bool(
            forKey:
                UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits
        )
        return formatter.string(for: remoteURI.user) ?? remoteURI.user
    }

    private func deliverIncomingCallNotification(
        controller: CallController,
        call: AKSIPCall,
        defaults: UserDefaults
    ) {
        guard
            controller.callActive,
            call.isMissed,
            call.state.rawValue != 6
        else {
            return
        }

        let callSource = formattedIncomingCallSource(
            call,
            defaults: defaults
        )
        let title = controller.displayedName?.isEmpty == false
            ? controller.displayedName!
            : callSource
        let description =
            controller.identityDetail?.isEmpty == false
                ? controller.identityDetail!
                : NSLocalizedString(
                    "calling",
                    comment: "Incoming-call notification description."
                )

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = description
        content.categoryIdentifier = "incoming-call"

        let request = UNNotificationRequest(
            identifier: controller.identifier,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog(
                    "Could not deliver incoming-call notification: %@",
                    error.localizedDescription
                )
            }
        }
    }

    private func startPlayingRingtoneOrLogError() {
        do {
            try ringtonePlayback.start()
        } catch {
            NSLog(
                "Could not start playing ringtone: %@",
                error.localizedDescription
            )
        }
    }
}

private func containsASCIILetter(_ value: String) -> Bool {
    value.range(of: "[A-Za-z]", options: .regularExpression) != nil
}


private func isTelephoneNumber(_ value: String) -> Bool {
    let digits = value.first == "+"
        ? value.dropFirst()
        : Substring(value)

    return !digits.isEmpty
        && digits.allSatisfy { $0 >= "0" && $0 <= "9" }
}
