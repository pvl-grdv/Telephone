//
//  AccountController.m
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

#import "AccountController.h"

@import UserNotifications;
@import UseCases;

#import "AKKeychain.h"
#import "AKNSString+Scanning.h"
#import "AKSIPURIFormatter.h"
#import "AKTelephoneNumberFormatter.h"

#import "AccountControllerToAccountAdapter.h"
#import "CallTransferController.h"
#import "SIPResponseLocalization.h"

#import "Telephone-Swift.h"

static NSString * const kRussian = @"ru";

static NSString *FormattedIncomingCallSource(AKSIPCall *call, NSUserDefaults *defaults) {
    AKSIPURI *remoteURI = call.remoteURI;
    if (remoteURI.user.length == 0) {
        return remoteURI.host ?: @"";
    }

    if (![remoteURI.user ak_isTelephoneNumber]) {
        return remoteURI.SIPAddress ?: remoteURI.user;
    }

    if (![defaults boolForKey:UserDefaultsKeys.formatTelephoneNumbers]) {
        return remoteURI.user;
    }

    AKTelephoneNumberFormatter *formatter = [[AKTelephoneNumberFormatter alloc] init];
    formatter.splitsLastFourDigits =
        [defaults boolForKey:UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits];
    return [formatter stringForObjectValue:remoteURI.user] ?: remoteURI.user;
}



@interface AccountController () <AccountPresentationCoordinatorDelegate>

@property(nonatomic, readonly) AKSIPUserAgent *userAgent;
@property(nonatomic, readonly) WorkspaceSleepStatus *sleepStatus;
@property(nonatomic, readonly) IncomingCallContactResolver *incomingCallContactResolver;

@property(nonatomic, readonly) AccountPresentationCoordinator *presentationCoordinator;

@property(nonatomic, readonly, getter=isAccountAdded) BOOL accountAdded;
@property(nonatomic, strong) NSTimer *reRegistrationTimer;
@property(nonatomic, copy) NSString *destinationToCall;

@end

@implementation AccountController

- (void)setEnabled:(BOOL)flag {
    _enabled = flag;
}

- (BOOL)attemptingToRegisterAccount {
    return self.presentationCoordinator.attemptingToRegister;
}

- (void)setAttemptingToRegisterAccount:(BOOL)flag {
    self.presentationCoordinator.attemptingToRegister = flag;
}

- (BOOL)attemptingToUnregisterAccount {
    return self.presentationCoordinator.attemptingToUnregister;
}

- (void)setAttemptingToUnregisterAccount:(BOOL)flag {
    self.presentationCoordinator.attemptingToUnregister = flag;
}

- (BOOL)shouldPresentRegistrationError {
    return self.presentationCoordinator.shouldPresentRegistrationError;
}

- (void)setShouldPresentRegistrationError:(BOOL)flag {
    self.presentationCoordinator.shouldPresentRegistrationError = flag;
}

- (BOOL)isAccountUnavailable {
    return self.presentationCoordinator.accountUnavailable;
}

- (void)setAccountUnavailable:(BOOL)flag {
    self.presentationCoordinator.accountUnavailable = flag;
}

- (BOOL)isAccountRegistered {
    return [[self account] isRegistered];
}

- (void)setAccountRegistered:(BOOL)flag {
    [self invalidateReRegistrationTimer];

    if ([self isAccountAdded]) {
        [self showConnectingState];
        
        [[self account] setRegistered:flag];
        
    } else {
        NSString *serviceName = [NSString stringWithFormat:@"SIP: %@", [[self account] registrar]];
        NSString *password = [AKKeychain passwordForService:serviceName account:[[self account] username]];
        
        [self showConnectingState];
        
        BOOL accountAdded = [[self userAgent] addAccount:[self account] withPassword:password];
        
        // Error connecting to registrar.
        if (accountAdded &&
            ![self isAccountRegistered] &&
            [[self account] registrationExpireTime] == kAKSIPAccountRegistrationExpireTimeNotSpecified &&
            [[self userAgent] isStarted]) {
            
            [self showUnavailableState];
            
            // Schedule account automatic re-registration timer.
            if ([self reRegistrationTimer] == nil) {
                NSTimeInterval reregistrationTimeInterval = (NSTimeInterval)[[self account] reregistrationTime];
                
                [self setReRegistrationTimer:
                 [NSTimer scheduledTimerWithTimeInterval:reregistrationTimeInterval
                                                  target:self
                                                selector:@selector(reRegistrationTimerTick:)
                                                userInfo:nil
                                                 repeats:YES]];
            }
            
            if ([self shouldPresentRegistrationError]) {
                NSString *statusText;
                NSString *preferredLocalization = [[NSBundle mainBundle] preferredLocalizations][0];
                if ([preferredLocalization isEqualToString:kRussian]) {
                    statusText = LocalizedStringForSIPResponseCode([[self account] registrationStatus]);
                } else {
                    statusText = [[self account] registrationStatusText];
                }
                
                NSString *error;
                if (statusText == nil) {
                    error = [NSString stringWithFormat:
                             NSLocalizedString(@"Error %ld", @"Error #."),
                             [[self account] registrationStatus]];
                    error = [error stringByAppendingString:@"."];
                } else {
                    error = [NSString stringWithFormat:
                             NSLocalizedString(@"The error was: “%ld %@”.", @"Error description."),
                             [[self account] registrationStatus], statusText];
                }
                
                [self showRegistrarConnectionErrorSheetWithError:error];
            }
            
            [self setShouldPresentRegistrationError:NO];
        }
    }
}

- (BOOL)isAccountAdded {
    return self.account.identifier != kAKSIPUserAgentInvalidIdentifier;
}

- (BOOL)canMakeCalls {
    return self.presentationCoordinator.canMakeCalls;
}

- (instancetype)initWithSIPAccount:(AKSIPAccount *)account
                accountDescription:(NSString *)accountDescription
                         userAgent:(AKSIPUserAgent *)userAgent
                  ringtonePlayback:(id<RingtonePlaybackUseCase>)ringtonePlayback
                       sleepStatus:(WorkspaceSleepStatus *)sleepStatus
       incomingCallContactResolver:(IncomingCallContactResolver *)incomingCallContactResolver
 callHistoryViewEventTargetFactory:(AsyncCallHistoryViewEventTargetFactory *)callHistoryViewEventTargetFactory {

    self = [super init];
    if (self == nil) {
        return nil;
    }

    _account = account;
    _account.delegate = self;
    _userAgent = userAgent;
    _ringtonePlayback = ringtonePlayback;
    _sleepStatus = sleepStatus;
    _incomingCallContactResolver = incomingCallContactResolver;

    _callControllers = [[NSMutableArray alloc] init];
    _accountDescription = [accountDescription copy];
    _destinationToCall = @"";

    _presentationCoordinator =
        [[AccountPresentationCoordinator alloc]
            initWithAccountDescription:_accountDescription
                     accountController:self
                             userAgent:_userAgent
     callHistoryViewEventTargetFactory:callHistoryViewEventTargetFactory
                               account:[[AccountControllerToAccountAdapter alloc] initWithController:self]
                              delegate:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(SIPUserAgentDidFinishStarting:)
                                                 name:AKSIPUserAgentDidFinishStartingNotification
                                               object:nil];
    
    return self;
}

- (void)dealloc {
    for (CallController *aCallController in [self callControllers]) {
        [aCallController close];
    }
    
    if ([[[self account] delegate] isEqual:self]) {
        [[self account] setDelegate:nil];
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_presentationCoordinator invalidate];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ controller", [self account]];
}

- (void)registerAccount {
    if (![[self userAgent] isStarted]) {
        [self setAttemptingToRegisterAccount:YES];
    }
    [self setAccountRegistered:YES];
}

- (void)unregisterAccount {
    if (![self isAccountAdded]) {
        [self setAttemptingToUnregisterAccount:YES];
    }
    [self setAccountRegistered:NO];
}

- (void)resetRegistrationIntent {
    [self.presentationCoordinator resetRegistrationIntent];
}

- (void)disableAccount {
    [[self callControllers] makeObjectsPerformSelector:@selector(close)];
    [self removeAccountFromUserAgent];
    [self setEnabled:NO];
    [self resetRegistrationIntent];
    [self hideWindow];
}

- (void)removeAccountFromUserAgent {
    NSAssert([self isEnabled], @"Account conroller must be enabled to remove account from the user agent.");
    [self invalidateReRegistrationTimer];
    [self showOfflineState];
    [[self userAgent] removeAccount:[self account]];
}

- (void)makeCallToURI:(AKSIPURI *)destinationURI
        phoneLabel:(NSString *)phoneLabel
        callTransferController:(CallTransferController *)callTransferController {
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    AKTelephoneNumberFormatter *telephoneNumberFormatter = [[AKTelephoneNumberFormatter alloc] init];
    [telephoneNumberFormatter setSplitsLastFourDigits:
     [defaults boolForKey:UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits]];
    
    NSString *enteredCallDestinationString = [[destinationURI user] copy];
    
    // Make user part a string of contiguous digits if needed.
    if (![[destinationURI user] ak_hasLetters]) {
        [destinationURI setUser:[telephoneNumberFormatter telephoneNumberFromString:[destinationURI user]]];
    }
    
    // Replace plus character if needed.
    if ([self substitutesPlusCharacter] &&
        [[destinationURI user] hasPrefix:@"+"]) {
        [destinationURI setUser:[[destinationURI user]
                                 stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                                         withString:[self plusCharacterSubstitution]]];
        enteredCallDestinationString = [enteredCallDestinationString
                                        stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                                                withString:[self plusCharacterSubstitution]];
    }
    
    // If it's a regular call, not a transfer, create the new CallController.
    CallController *aCallController;
    if (callTransferController == nil) {
        aCallController = [[CallController alloc] initWithWindowNibName:@"Call"
                                                      accountController:self
                                                              userAgent:self.userAgent
                                                               delegate:self];
    } else {
        aCallController = callTransferController;
    }
    
    [aCallController setNameFromAddressBook:[destinationURI displayName]];
    [aCallController setPhoneLabelFromAddressBook:phoneLabel];
    [aCallController setEnteredCallDestination:enteredCallDestinationString];
    [[self callControllers] addObject:aCallController];
    
    // Set title.
    if ([[destinationURI host] length] > 0) {
        [aCallController setTitle:[destinationURI SIPAddress]];
        
    } else if (![enteredCallDestinationString ak_hasLetters]) {
        if ([enteredCallDestinationString ak_isTelephoneNumber] && [defaults boolForKey:UserDefaultsKeys.formatTelephoneNumbers]) {
            [aCallController setTitle:[telephoneNumberFormatter stringForObjectValue:enteredCallDestinationString]];
        } else {
            [aCallController setTitle:enteredCallDestinationString];
        }
    } else {
        [aCallController setTitle:[[SIPAddress alloc] initWithUser:destinationURI.user host:self.account.uri.host].stringValue];
    }
    
    // Set displayed name.
    if ([[destinationURI displayName] length] > 0) {
        [aCallController setDisplayedName:[destinationURI displayName]];
        
    } else {
        if ([[destinationURI host] length] > 0) {
            [aCallController setDisplayedName:[destinationURI SIPAddress]];
            
        } else if ([enteredCallDestinationString ak_isTelephoneNumber] &&
                   [defaults boolForKey:UserDefaultsKeys.formatTelephoneNumbers]) {
            
            [aCallController setDisplayedName:
             [telephoneNumberFormatter stringForObjectValue:enteredCallDestinationString]];
            
        } else {
            [aCallController setDisplayedName:enteredCallDestinationString];
        }
    }
    
    // Clean display-name part of the destination URI to prevent another call
    // party from seeing local Address Book records.
    [destinationURI setDisplayName:@""];
    
    if ([[destinationURI host] length] == 0) {
        [destinationURI setHost:[[[self account] uri] host]];
    }
    
    // Set URI for redial.
    [aCallController setRedialURI:destinationURI];
    
    [aCallController prepareForCall];

    if ([phoneLabel length] > 0) {
        [aCallController setStatus:
         [NSString stringWithFormat:NSLocalizedString(@"calling %@...",
                                                      @"Outgoing call in progress. Calling specific phone "
                                                       "type (mobile, home, etc)."), phoneLabel]];
    } else {
        [aCallController setStatus:NSLocalizedString(@"calling...", @"Outgoing call in progress.")];
    }
    
    if (callTransferController == nil) {
        [aCallController showWindow:self];
    }
    
    // Finally, make a call.
    [self.account makeCallTo:destinationURI completion:^(AKSIPCall *call) {
        if (call != nil) {
            [aCallController setCall:call];
            [aCallController setCallActive:YES];
        } else {
            [aCallController showEndedCallView];
            [aCallController setStatus:NSLocalizedString(@"Call Failed", @"Call failed.")];
        }
    }];
}

- (void)makeCallToURI:(AKSIPURI *)destinationURI phoneLabel:(NSString *)phoneLabel {
    if (self.isAccountAdded) {
        [self makeCallToURI:destinationURI phoneLabel:phoneLabel callTransferController:nil];
    }
}

- (void)makeCallToDestinationRegisteringAccountIfNeeded:(SanitizedCallDestination *)destination {
    if (![self isAccountAdded]) {
        [self setDestinationToCall:destination.value];
        [self registerAccount];
    } else {
        [self makeCallToDestination:destination.value];
    }
}

- (void)makeCallToDestination:(NSString *)destination {
    [self.presentationCoordinator makeCallToDestination:destination];
}

- (void)makeCallToSavedDestination {
    [self makeCallToDestination:[self destinationToCall]];
    [self setDestinationToCall:@""];
}

- (void)showWindow {
    [self.presentationCoordinator showWindow];
}

- (void)showWindowWithoutMakingKey {
    [self.presentationCoordinator showWindowWithoutMakingKey];
}

- (void)hideWindow {
    [self.presentationCoordinator hideWindow];
}

- (void)changeAccountState:(AccountAvailabilityState)state {
    [self invalidateReRegistrationTimer];
    switch (state) {
        case AccountAvailabilityStateOffline:
            self.accountUnavailable = NO;
            [self removeAccountFromUserAgent];
            break;
        case AccountAvailabilityStateAvailable:
            self.accountUnavailable = NO;
            self.shouldPresentRegistrationError = YES;
            [self registerAccount];
            break;
        case AccountAvailabilityStateUnavailable:
            if (self.isAccountRegistered || !self.isAccountAdded) {
                self.accountUnavailable = YES;
                self.shouldPresentRegistrationError = YES;
                [self unregisterAccount];
            }
            break;
    }
}

- (BOOL)changeAccountStateRawValue:(NSInteger)state {
    if (!self.isEnabled) {
        return NO;
    }

    switch (state) {
        case AccountAvailabilityStateOffline:
        case AccountAvailabilityStateAvailable:
        case AccountAvailabilityStateUnavailable:
            [self changeAccountState:(AccountAvailabilityState)state];
            return YES;
        default:
            return NO;
    }
}

- (void)showRegistrarConnectionErrorSheetWithError:(NSString *)error {
    [self.presentationCoordinator
        showRegistrarConnectionErrorWithRegistrar:self.account.registrar.stringValue
                                            error:error];
}


- (void)showAvailableState {
    [self.presentationCoordinator showAvailableState];
}

- (void)showUnavailableState {
    [self.presentationCoordinator showUnavailableState];
}

- (void)showOfflineState {
    [self.presentationCoordinator showOfflineState];
}

- (void)showConnectingState {
    [self.presentationCoordinator showConnectingState];
}

- (void)reRegistrationTimerTick:(NSTimer *)theTimer {
    [[self account] setRegistered:YES];
}

- (void)invalidateReRegistrationTimer {
    [self.reRegistrationTimer invalidate];
    self.reRegistrationTimer = nil;
}

#pragma mark - AccountPresentationCoordinatorDelegate

- (void)accountPresentationCoordinator:(AccountPresentationCoordinator *)controller didChangeAccountState:(AccountAvailabilityState)state {
    [self changeAccountState:state];
}


#pragma mark - AKSIPAccountDelegate

// When account registration changes, make appropriate modifications to the UI. A call can also be made from here if
// the user called from the Address Book or from the application URL handler.
- (void)SIPAccountRegistrationDidChange:(AKSIPAccount *)account {
    // The account can be not added if notification on the main thread was delivered after
    // user agent had removed the account. Don't bother in that case.
    if (![self isAccountAdded]) {
        return;
    }
    
    if ([[self account] isRegistered]) {
        [self invalidateReRegistrationTimer];

        // If the account was offline and the user chose Unavailable state, -unregisterAccount will add the account
        // to the user agent. User agent will register the account. Set the account to Unavailable (unregister it) here.
        if ([self attemptingToUnregisterAccount]) {
            [self unregisterAccount];
            
        } else {
            [self setAccountUnavailable:NO];
            [self showAvailableState];
            if ([[self destinationToCall] length] > 0) {
                [self makeCallToSavedDestination];
            }
        }
        
    } else {
        [self showUnavailableState];
        
        // Handle authentication failure
        if ([[self account] registrationStatus] == PJSIP_SC_UNAUTHORIZED &&
            [[self account] registrationErrorCode] == PJSIP_EFAILEDCREDENTIAL) {

            [self.presentationCoordinator showAuthenticationFailure];

        } else if (([[self account] registrationStatus] / 100 != 2) &&
                   ([[self account] registrationExpireTime] == kAKSIPAccountRegistrationExpireTimeNotSpecified)) {
            // Raise a sheet if connection to the registrar failed. If last registration status is 2xx and expiration
            // interval is not specified, it is unregistration, not failure. Condition of failure is: last registration
            // status != 2xx AND expiration interval is not specified.
            
            if ([[self userAgent] isStarted]) {
                if ([self shouldPresentRegistrationError]) {
                    NSString *statusText;
                    NSString *preferredLocalization = [[NSBundle mainBundle] preferredLocalizations][0];
                    if ([preferredLocalization isEqualToString:kRussian]) {
                        statusText = LocalizedStringForSIPResponseCode([[self account] registrationStatus]);
                    } else {
                        statusText = [[self account] registrationStatusText];
                    }
                    
                    NSString *error;
                    if (statusText == nil) {
                        error = [NSString stringWithFormat:NSLocalizedString(@"Error %ld", @"Error #."),
                                 [[self account] registrationStatus]];
                        error = [error stringByAppendingString:@"."];
                    } else {
                        error = [NSString stringWithFormat:
                                 NSLocalizedString(@"The error was: “%ld %@”.", @"Error description."),
                                 [[self account] registrationStatus], statusText];
                    }
                    
                    [self showRegistrarConnectionErrorSheetWithError:error];
                    
                } else {
                    // Schedule account automatic re-registration timer.
                    if ([self reRegistrationTimer] == nil) {
                        NSTimeInterval reregistrationTimeInterval = (NSTimeInterval)[[self account] reregistrationTime];
                        
                        [self setReRegistrationTimer:
                         [NSTimer scheduledTimerWithTimeInterval:reregistrationTimeInterval
                                                          target:self
                                                        selector:@selector(reRegistrationTimerTick:)
                                                        userInfo:nil
                                                         repeats:YES]];
                    }
                }
            }
        }
    }
    
    [self setAttemptingToRegisterAccount:NO];
    [self setAttemptingToUnregisterAccount:NO];
    [self setShouldPresentRegistrationError:NO];
}

- (void)SIPAccountWillRemove:(AKSIPAccount *)account {
    [self invalidateReRegistrationTimer];
}

- (void)SIPAccount:(AKSIPAccount *)account didReceiveCall:(AKSIPCall *)aCall {
    if ([self isAccountUnavailable]) {
        [aCall replyWithTemporarilyUnavailable];
        return;
    } else if (![[NSUserDefaults standardUserDefaults] boolForKey:UserDefaultsKeys.callWaiting]) {
        for (CallController *callController in [self callControllers]) {
            if ([callController isCallActive]) {
                [aCall replyWithBusyHere];
                return;
            }
        }
    }

    CallController *aCallController = [[CallController alloc] initWithWindowNibName:@"Call"
                                                                  accountController:self
                                                                          userAgent:self.userAgent
                                                                           delegate:self];

    [aCallController setCall:aCall];
    [aCallController setCallActive:YES];
    [[self callControllers] addObject:aCallController];

    AKSIPURIFormatter *SIPURIFormatter = [[AKSIPURIFormatter alloc] init];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [SIPURIFormatter setFormatsTelephoneNumbers:[defaults boolForKey:UserDefaultsKeys.formatTelephoneNumbers]];
    [SIPURIFormatter setTelephoneNumberFormatterSplitsLastFourDigits:
     [defaults boolForKey:UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits]];

    NSString *callSource = FormattedIncomingCallSource(aCall, defaults);
    CallerIdentityPresentation *identity =
        [CallerIdentityPresentation
            makeWithSIPDisplayName:aCall.remoteURI.displayName ?: @""
                        callSource:callSource
                       contactName:@""
                      organization:@""
                             label:@""];
    NSString *callingStatus = NSLocalizedString(@"calling",
                                                @"John Smith calling. Somebody is calling us right "
                                                 "now. Call status string. Deliberately in lower case, "
                                                 "translators should do the same, if possible.");

    [aCallController setDisplayedName:identity.primary];
    [aCallController setIdentityDetail:identity.detail];
    [aCallController setStatus:callingStatus];
    [aCallController setRedialURI:[aCall remoteURI]];
    [aCallController showIncomingCallView];
    [aCallController showWindow:nil];

    // Do not make an incoming SIP call wait for Contacts I/O. Ring and present
    // immediately, then enrich the window/notification from the shared modern
    // Contacts index when the asynchronous lookup completes.
    [self startPlayingRingtoneOrLogError];
    [aCall sendRingingNotification];

    NSString *domain = self.account.uri.host ?: @"";
    AKSIPURI *remoteURI = aCall.remoteURI;
    [self.incomingCallContactResolver resolveWithUser:remoteURI.user
                                                  host:remoteURI.host
                                           displayName:remoteURI.displayName
                                                domain:domain
                                            completion:^(IncomingCallContact *contact) {
        // Contact lookup is asynchronous. The caller may have hung up or the
        // call may have been answered while the lookup was in flight. Do not
        // resurrect a stale actionable incoming-call notification.
        if (!aCallController.isCallActive ||
            !aCall.isMissed ||
            aCall.state == kAKSIPCallDisconnectedState) {
            return;
        }

        if (contact != nil) {
            [aCallController setNameFromAddressBook:contact.name];
            [aCallController setOrganizationFromAddressBook:contact.organization];
            [aCallController setPhoneLabelFromAddressBook:contact.label];

            NSString *callSource = FormattedIncomingCallSource(aCall, defaults);
            CallerIdentityPresentation *identity =
                [CallerIdentityPresentation
                    makeWithSIPDisplayName:aCall.remoteURI.displayName ?: @""
                                callSource:callSource
                               contactName:contact.name
                              organization:contact.organization
                                     label:contact.label];

            [aCallController setDisplayedName:identity.primary];
            [aCallController setIdentityDetail:identity.detail];
        }

        [self deliverIncomingCallNotificationForController:aCallController call:aCall defaults:defaults];
    }];
}

- (void)deliverIncomingCallNotificationForController:(CallController *)aCallController
                                                call:(AKSIPCall *)aCall
                                            defaults:(NSUserDefaults *)defaults {
    if (!aCallController.isCallActive ||
        !aCall.isMissed ||
        aCall.state == kAKSIPCallDisconnectedState) {
        return;
    }

    NSString *callSource = FormattedIncomingCallSource(aCall, defaults);
    NSString *notificationTitle = aCallController.displayedName;
    if (notificationTitle.length == 0) {
        notificationTitle = callSource;
    }

    NSString *notificationDescription = aCallController.identityDetail;
    if (notificationDescription.length == 0) {
        notificationDescription = NSLocalizedString(
            @"calling",
            @"Somebody is calling us right now. User notification description."
        );
    }

    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = notificationTitle ?: @"";
    content.body = notificationDescription ?: @"";
    content.categoryIdentifier = @"incoming-call";

    UNNotificationRequest *request =
        [UNNotificationRequest requestWithIdentifier:aCallController.identifier
                                             content:content
                                             trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter]
        addNotificationRequest:request
         withCompletionHandler:^(NSError *error) {
            if (error != nil) {
                NSLog(@"Could not deliver incoming-call notification: %@", error);
            }
        }];
}

- (void)startPlayingRingtoneOrLogError {
    NSError *error;
    BOOL success = [self.ringtonePlayback startAndReturnError:&error];
    if (!success) {
        NSLog(@"Could not start playing ringtone: %@", error);
    }
}


#pragma mark - CallControllerDelegate

- (void)callControllerWillClose:(CallController *)callController {
    [self.callControllers removeObject:callController];
    [(AppController *)[NSApp delegate] updateDockTileBadgeLabel];
}


#pragma mark - AKSIPUserAgent notifications

- (void)SIPUserAgentDidFinishStarting:(NSNotification *)notification {
    if (![[notification object] isStarted]) {
        [self showOfflineState];
        
        return;
    }
    
    if ([self attemptingToRegisterAccount]) {
        [self registerAccount];
    } else if ([self attemptingToUnregisterAccount]) {
        [self unregisterAccount];
    }
}

@end
