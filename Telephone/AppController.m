//
//  AppController.m
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

#import "AppController.h"

@import UserNotifications;
@import UseCases;

#import "AKNetworkReachability.h"
#import "AKNSString+Scanning.h"
#import "AKSIPAccount.h"
#import "AKSIPCall.h"

#import "AccountController.h"
#import "AccountControllers.h"
#import "CallController.h"
#import "NameServers.h"

#import "Telephone-Swift.h"

static const NSTimeInterval kNetworkPathChangeCoalescingDelay = 0.5;

NS_ASSUME_NONNULL_BEGIN

@interface AppController () <AKSIPUserAgentDelegate, UNUserNotificationCenterDelegate, NameServersChangeEventTarget, PreferencesControllerDelegate>

@property(nonatomic, readonly) AKSIPUserAgent *userAgent;
@property(nonatomic, readonly) AccountControllers *accountControllers;
@property(nonatomic, readonly) AccountSetupPresentationController *accountSetupPresentationController;
@property(nonatomic, readonly) ApplicationDialogController *applicationDialogController;
@property(nonatomic) BOOL shouldRegisterAllAccounts;
@property(nonatomic) BOOL shouldRestartUserAgentASAP;
@property(nonatomic, getter=isTerminating) BOOL terminating;
@property(nonatomic, getter=isTerminationConfirmed) BOOL terminationConfirmed;
@property(nonatomic) BOOL shouldPresentUserAgentLaunchError;
@property(nonatomic, readonly) AccountsCommandModel *accountsCommandModel;

@property(nonatomic, readonly) CompositionRoot *compositionRoot;
@property(nonatomic, readonly) PreferencesController *preferencesController;
@property(nonatomic, readonly) id<RingtonePlaybackUseCase> ringtonePlayback;
@property(nonatomic, readonly) id<UseCase> userAgentStart;
@property(nonatomic, readonly) WorkspaceSleepStatus *sleepStatus;
@property(nonatomic, readonly) AsyncCallHistoryViewEventTargetFactory *callHistoryViewEventTargetFactory;
@property(nonatomic, getter=isFinishedLaunching) BOOL finishedLaunching;
@property(nonatomic, copy) NSString *destinationToCall;
@property(nonatomic, getter=isUserSessionActive) BOOL userSessionActive;
@property(nonatomic, readonly) NameServers *nameServers;
@property(nonatomic, readonly) AKNetworkReachability *networkReachability;

@end

NS_ASSUME_NONNULL_END


@implementation AppController

@synthesize accountSetupPresentationController = _accountSetupPresentationController;

- (AccountSetupPresentationController *)accountSetupPresentationController {
    if (_accountSetupPresentationController == nil) {
        _accountSetupPresentationController = [[AccountSetupPresentationController alloc] init];
    }
    return _accountSetupPresentationController;
}

- (instancetype)init {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _compositionRoot = [[CompositionRoot alloc] initWithPreferencesControllerDelegate:self
                                                         nameServersChangeEventTarget:self];

    _userAgent = _compositionRoot.userAgent;
    [[self userAgent] setDelegate:self];
    _preferencesController = _compositionRoot.preferencesController;
    _ringtonePlayback = _compositionRoot.ringtonePlayback;
    _userAgentStart = _compositionRoot.userAgentStart;
    _sleepStatus = _compositionRoot.workstationSleepStatus;
    _callHistoryViewEventTargetFactory = _compositionRoot.callHistoryViewEventTargetFactory;
    _destinationToCall = @"";
    _userSessionActive = YES;
    _accountControllers = _compositionRoot.accountControllers;
    _applicationDialogController = [[ApplicationDialogController alloc] init];
    _accountsCommandModel =
        [[AccountsCommandModel alloc] initWithControllers:_accountControllers];
    _nameServers = _compositionRoot.nameServers;
    _networkReachability = [AKNetworkReachability networkReachability];
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

    [notificationCenter addObserver:self
                           selector:@selector(networkPathDidChange:)
                               name:AKNetworkReachabilityDidChangeNotification
                             object:_networkReachability];

    [notificationCenter addObserver:self
                           selector:@selector(accountSetupControllerDidAddAccount:)
                               name:[AccountSetupPresentationController didAddAccountNotificationName]
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(SIPCallCalling:)
                               name:AKSIPCallCallingNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(SIPCallIncoming:)
                               name:AKSIPCallIncomingNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(SIPCallConnecting:)
                               name:AKSIPCallConnectingNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(SIPCallDidDisconnect:)
                               name:AKSIPCallDidDisconnectNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(authenticationFailureControllerDidChangeUsernameAndPassword:)
                               name:@"AKAuthenticationFailureControllerDidChangeUsernameAndPassword"
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(applicationDialogDidConfirmQuit:)
                               name:[ApplicationDialogController quitConfirmedNotificationName]
                             object:nil];
    
    notificationCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
    [notificationCenter addObserver:self
                           selector:@selector(workspaceWillSleep:)
                               name:NSWorkspaceWillSleepNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(workspaceDidWake:)
                               name:NSWorkspaceDidWakeNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(workspaceSessionDidResignActive:)
                               name:NSWorkspaceSessionDidResignActiveNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(workspaceSessionDidBecomeActive:)
                               name:NSWorkspaceSessionDidBecomeActiveNotification
                             object:nil];
    
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(handleNetworkPathChange)
                                               object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}

- (void)stopUserAgent {
    [self.accountControllers hangUpCallsAndRemoveAccountsFromUserAgent];
    [self.userAgent stop];
}

- (void)stopUserAgentAndWait {
    [self.accountControllers hangUpCallsAndRemoveAccountsFromUserAgent];
    [self.userAgent stopAndWait];
}

- (void)restartUserAgent {
    if ([[self userAgent] isStarted]) {
        [self setShouldRegisterAllAccounts:YES];
        [self stopUserAgent];
    }
}

- (void)restartUserAgentAfterDelayOrMarkForRestart {
    if (!self.accountControllers.haveActiveCallControllers) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(restartUserAgent) object:nil];
        [self performSelector:@selector(restartUserAgent) withObject:nil afterDelay:3.0];
    } else {
        self.shouldRestartUserAgentASAP = YES;
    }
}

- (void)copySettings {
    [self.compositionRoot.helpMenuActionTarget copySettings];
}

- (void)showLogFile {
    [self.compositionRoot.helpMenuActionTarget showLogFile];
}

- (void)openHomepage {
    [self.compositionRoot.helpMenuActionTarget openHomepage];
}

- (void)openFAQ {
    [self.compositionRoot.helpMenuActionTarget openFAQ];
}

- (id)accountsCommandModelForSwiftUI {
    return self.accountsCommandModel;
}

- (void)showPreferencesForSwiftUI {
    [self.preferencesController showWindowCentered];
}

#if DEBUG
- (void)showPreferencesForUITesting {
    [self.preferencesController showWindowForUITesting];
}

- (void)showAccountSetupForUITesting {
    [self.accountSetupPresentationController showFirstRun];
}
#endif

- (BOOL)makeCallFromAppIntentWithDestination:(NSString *)destination {
    if (!self.isFinishedLaunching || ![self canMakeCall]) {
        return NO;
    }

    SanitizedCallDestination *sanitized =
        [[SanitizedCallDestination alloc] initWithString:destination];
    if (sanitized == nil) {
        return NO;
    }

    [self.accountControllers.enabled.firstObject
        makeCallToDestinationRegisteringAccountIfNeeded:sanitized];
    return YES;
}

- (BOOL)setAccountAvailabilityFromAppIntentWithUUID:(NSString *)uuid
                                              state:(NSInteger)state {
    for (AccountController *controller in self.accountControllers.enabled) {
        if ([controller.account.uuid isEqualToString:uuid]) {
            return [controller changeAccountStateRawValue:state];
        }
    }
    return NO;
}

- (void)updateDockTileBadgeLabel {
    NSString *badgeString;
    NSInteger badgeNumber = self.accountControllers.unhandledIncomingCallsCount;
    if (badgeNumber == 0) {
        badgeString = @"";
    } else {
        badgeString = [NSString stringWithFormat:@"%ld", badgeNumber];
    }
    
    [[NSApp dockTile] setBadgeLabel:badgeString];
}

- (void)showAccountPreferencesIfNeeded {
    if (self.accountControllers.enabled.count == 0)  {
        [self.preferencesController showWindowCentered];
        [self.preferencesController showAccounts];
    }
}

- (AccountController *)accountControllerWithDictionary:(NSDictionary *)dict {
    AKSIPAccount *account = [[AKSIPAccount alloc] initWithDictionary:dict parser:self.userAgent.parser];

    NSString *description = dict[AKSIPAccountKeys.desc];
    if ([description length] == 0) {
        description = account.SIPAddress;
    }

    AccountController *controller = [[AccountController alloc] initWithSIPAccount:account
                                                               accountDescription:description
                                                                        userAgent:self.userAgent
                                                                 ringtonePlayback:self.ringtonePlayback
                                                                      sleepStatus:self.sleepStatus
                                                      incomingCallContactResolver:self.compositionRoot.incomingCallContactResolver
                                                callHistoryViewEventTargetFactory:self.callHistoryViewEventTargetFactory];

    [controller setEnabled:[dict[UserDefaultsKeys.accountEnabled] boolValue]];
    [controller setSubstitutesPlusCharacter:[dict[UserDefaultsKeys.substitutePlusCharacter] boolValue]];
    [controller setPlusCharacterSubstitution:dict[UserDefaultsKeys.plusCharacterSubstitutionString]];

    return controller;
}


#pragma mark -
#pragma mark AccountSetupController delegate

- (void)accountSetupControllerDidAddAccount:(NSNotification *)notification {
    BOOL isFirstLaunch = !self.isFinishedLaunching;
    AccountController *controller = [self accountControllerWithDictionary:notification.userInfo];

    [self.accountControllers addController:controller];
    [self.accountControllers updateCallsShouldDisplayAccountInfo];
    [self.accountsCommandModel update];

    [controller showWindowWithoutMakingKey];

    if (isFirstLaunch) {
        self.finishedLaunching = YES;

        if (self.networkReachability.isReachable) {
            self.shouldPresentUserAgentLaunchError = YES;
            [self.accountControllers registerAllAccounts];
        }
        [self makeCallAfterLaunchIfNeeded];
    } else if (controller.isEnabled) {
        [controller registerAccount];
    }
}


#pragma mark -
#pragma mark PreferencesController delegate

- (void)preferencesControllerDidRemoveAccount:(NSNotification *)notification {
    NSInteger index = [notification.userInfo[kAccountIndex] integerValue];
    AccountController *controller = self.accountControllers[index];
    
    if ([controller isEnabled]) {
        [controller removeAccountFromUserAgent];
    }
    
    [self.accountControllers removeControllerAtIndex:index];
    [self.accountControllers updateCallsShouldDisplayAccountInfo];
    [self.accountsCommandModel update];
}

- (void)preferencesControllerDidChangeAccountEnabled:(NSNotification *)notification {
    NSUInteger index = [[notification userInfo][kAccountIndex] integerValue];
    
    NSDictionary *account = [NSUserDefaults.standardUserDefaults arrayForKey:UserDefaultsKeys.accounts][index];

    if ([account[UserDefaultsKeys.accountEnabled] boolValue]) {
        AccountController *controller = [self accountControllerWithDictionary:account];
        [controller setAccountUnavailable:NO];

        self.accountControllers[index] = controller;
        
        [controller showWindowWithoutMakingKey];

        [controller registerAccount];
        
    } else {
        AccountController *controller = self.accountControllers[index];
        [controller disableAccount];
    }
    
    [self.accountControllers updateCallsShouldDisplayAccountInfo];
    [self.accountsCommandModel update];
}

- (void)preferencesControllerDidSwapAccounts:(NSNotification *)notification {
    NSDictionary *userInfo = [notification userInfo];
    NSInteger sourceIndex = [userInfo[kSourceIndex] integerValue];
    NSInteger destinationIndex = [userInfo[kDestinationIndex] integerValue];
    
    if (sourceIndex == destinationIndex) {
        return;
    }
    
    [self.accountControllers insertController:self.accountControllers[sourceIndex] atIndex:destinationIndex];
    if (sourceIndex < destinationIndex) {
        [self.accountControllers removeControllerAtIndex:sourceIndex];
    } else if (sourceIndex > destinationIndex) {
        [self.accountControllers removeControllerAtIndex:(sourceIndex + 1)];
    }
    
    [self.accountsCommandModel update];
}

- (void)preferencesControllerDidChangeNetworkSettings:(NSNotification *)notification {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    [[self userAgent] setTransportPort:[defaults integerForKey:UserDefaultsKeys.transportPort]];
    [[self userAgent] setSTUNServerHost:[defaults stringForKey:UserDefaultsKeys.stunServerHost]];
    [[self userAgent] setSTUNServerPort:[defaults integerForKey:UserDefaultsKeys.stunServerPort]];
    [[self userAgent] setUsesICE:[defaults boolForKey:UserDefaultsKeys.useICE]];
    [[self userAgent] setOutboundProxyHost:[defaults stringForKey:UserDefaultsKeys.outboundProxyHost]];
    [[self userAgent] setOutboundProxyPort:[defaults integerForKey:UserDefaultsKeys.outboundProxyPort]];
    
    if ([defaults boolForKey:UserDefaultsKeys.useDNSSRV]) {
        [[self userAgent] setNameServers:self.nameServers.all];
    } else {
        [[self userAgent] setNameServers:nil];
    }
    
    // Restart SIP user agent.
    if ([[self userAgent] isStarted]) {
        [self setShouldPresentUserAgentLaunchError:YES];
        [self restartUserAgent];
    }
}


#pragma mark -
#pragma mark AKSIPUserAgentDelegate

- (BOOL)SIPUserAgentShouldAddAccount:(AKSIPAccount *)account {
    if (self.userAgent.isStarted) {
        return YES;
    } else {
        if (self.userAgent.state == AKSIPUserAgentStateStopped) {
            [self.userAgentStart execute];
        }
        return NO;
    }
}

- (void)SIPUserAgentDidFinishStarting:(NSNotification *)notification {
    if ([[self userAgent] isStarted]) {
        if ([self shouldRegisterAllAccounts]) {
            [self.accountControllers registerAllAccounts];
        }
        
        [self setShouldRegisterAllAccounts:NO];
        [self setShouldRestartUserAgentASAP:NO];
        
    } else {
        NSLog(@"Could not start SIP user agent. "
              "Please check your network connection and STUN server settings.");
        
        [self setShouldRegisterAllAccounts:NO];
        
        // Set |shouldPresentUserAgentLaunchError| if needed and if it wasn't set
        // somewhere else.
        if (![self shouldPresentUserAgentLaunchError]) {
            // Check whether any AccountController is trying to register or unregister
            // an acount. If so, we should present SIP user agent launch error.
            for (AccountController *controller in self.accountControllers.enabled) {
                if ([controller shouldPresentRegistrationError]) {
                    [self setShouldPresentUserAgentLaunchError:YES];
                    [controller resetRegistrationIntent];
                }
            }
        }
        
        if ([self shouldPresentUserAgentLaunchError] &&
            !self.applicationDialogController.isPresenting) {
            [self.applicationDialogController showSIPUserAgentLaunchError];
        }
    }
    
    [self setShouldPresentUserAgentLaunchError:NO];
}

- (void)SIPUserAgentDidFinishStopping:(NSNotification *)notification {
    if ([self isTerminating]) {
        [NSApp replyToApplicationShouldTerminate:YES];
        
    } else if ([self shouldRegisterAllAccounts]) {
        if (self.accountControllers.enabled.count > 0) {
            [[self userAgentStart] execute];
        } else {
            [self setShouldRegisterAllAccounts:NO];
        }
    }
}

- (void)SIPUserAgentDidDetectNAT:(NSNotification *)notification {
    if ([[self userAgent] detectedNATType] != kAKNATTypeBlocked) {
        return;
    }

    [self.applicationDialogController showSTUNCommunicationError];
}



#pragma mark -
#pragma mark NSApplication delegate methods

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"NSFullScreenMenuItemEverywhere"];
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (url == nil) {
        return;
    }

    SanitizedCallDestination *destination = [[SanitizedCallDestination alloc] initWithURL:url];
    if (destination == nil) {
        NSLog(@"Ignoring unsupported call URL: %@", url);
        return;
    }

    [self makeCallOrRememberDestination:destination.value];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self.compositionRoot.defaultAppSettings registerDefaults];
    [self.compositionRoot.settingsMigration execute];

    if ([TelephoneUITestSupport handleLaunchWithAppController:self]) {
        [self setFinishedLaunching:YES];
        return;
    }

    [self configureUserAgent];
    [self configureUserNotifications];
    NSApp.servicesProvider = self;
    NSArray *accounts = [NSUserDefaults.standardUserDefaults arrayForKey:UserDefaultsKeys.accounts];
    if (accounts.count == 0) {
        [self.accountSetupPresentationController showFirstRun];
        return;
    }
    for (NSUInteger i = 0; i < accounts.count; ++i) {
        AccountController *controller = [self accountControllerWithDictionary:accounts[i]];
        [self.accountControllers addController:controller];
        if (![controller isEnabled]) {
            continue;
        }
        [controller showWindow];
    }
    [self.accountControllers updateCallsShouldDisplayAccountInfo];
    [self.accountsCommandModel update];
    [self setFinishedLaunching:YES];
    if (self.networkReachability.isReachable) {
        [self setShouldPresentUserAgentLaunchError:YES];
        [self.accountControllers registerAllAccounts];
    }
    [self makeCallAfterLaunchIfNeeded];
    [self.compositionRoot.orphanLogFileRemoval performSelector:@selector(execute) withObject:nil afterDelay:0];
    [self showAccountPreferencesIfNeeded];
}

- (void)configureUserAgent {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults boolForKey:UserDefaultsKeys.useDNSSRV]) {
        self.userAgent.nameServers = self.nameServers.all;
    }
    self.userAgent.outboundProxyHost = [defaults stringForKey:UserDefaultsKeys.outboundProxyHost];
    self.userAgent.outboundProxyPort = [defaults integerForKey:UserDefaultsKeys.outboundProxyPort];
    self.userAgent.STUNServerHost = [defaults stringForKey:UserDefaultsKeys.stunServerHost];
    self.userAgent.STUNServerPort = [defaults integerForKey:UserDefaultsKeys.stunServerPort];
    self.userAgent.userAgentString = [NSString stringWithFormat:@"%@ %@",
                                      NSBundle.mainBundle.infoDictionary[@"CFBundleName"],
                                      NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]];
    self.userAgent.logFileName = self.compositionRoot.logFileURL.pathValue;
    self.userAgent.logLevel = [defaults integerForKey:UserDefaultsKeys.logLevel];
    self.userAgent.consoleLogLevel = [defaults integerForKey:UserDefaultsKeys.consoleLogLevel];
    self.userAgent.detectsVoiceActivity = [defaults boolForKey:UserDefaultsKeys.voiceActivityDetection];
    self.userAgent.usesICE = [defaults boolForKey:UserDefaultsKeys.useICE];
    self.userAgent.usesQoS = [defaults boolForKey:UserDefaultsKeys.useQoS];
    self.userAgent.transportPort = [defaults integerForKey:UserDefaultsKeys.transportPort];
    self.userAgent.usesG711Only = [defaults boolForKey:UserDefaultsKeys.useG711Only];
    self.userAgent.locksCodec = [defaults boolForKey:UserDefaultsKeys.lockCodec];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag {
    if (self.userAgent.hasUnansweredIncomingCalls) {
        [self.accountControllers showIncomingCallWindows];
    } else if (!flag && self.accountControllers.enabled.count > 0) {
        [self.accountControllers.enabled.firstObject showWindow];
    }
    return YES;
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification {
    [[UNUserNotificationCenter currentNotificationCenter] removeAllDeliveredNotifications];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (self.accountControllers.haveActiveCallControllers &&
        !self.isTerminationConfirmed) {
        [self.applicationDialogController showQuitConfirmation];
        return NSTerminateCancel;
    }

    if ([[self userAgent] isStarted]) {
        [self setTerminating:YES];
        [self stopUserAgent];

        // Terminate after SIP user agent is stopped in the secondary thread.
        // We should send replyToApplicationShouldTerminate: to NSApp from
        // AKSIPUserAgentDidFinishStoppingNotification.
        return NSTerminateLater;
    }

    return NSTerminateNow;
}

- (void)applicationDialogDidConfirmQuit:(NSNotification *)notification {
    self.terminationConfirmed = YES;
    [NSApp terminate:self];
}



#pragma mark -
#pragma mark AKSIPCall notifications

- (void)SIPCallCalling:(NSNotification *)notification {
    [self updateDockTileBadgeLabel];
}

- (void)SIPCallIncoming:(NSNotification *)notification {
    [self updateDockTileBadgeLabel];
}

- (void)SIPCallConnecting:(NSNotification *)notification {
    [self updateDockTileBadgeLabel];
}

- (void)SIPCallDidDisconnect:(NSNotification *)notification {
    [self updateDockTileBadgeLabel];
    if (self.shouldRestartUserAgentASAP && !self.accountControllers.haveActiveCallControllers) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(restartUserAgent) object:nil];
        [self setShouldRestartUserAgentASAP:NO];
        [self restartUserAgent];
    }
}


#pragma mark -
#pragma mark AuthenticationFailureController notifications

- (void)authenticationFailureControllerDidChangeUsernameAndPassword:(NSNotification *)notification {
    AccountController *controller = [[notification object] accountController];
    NSInteger index = [self.accountControllers indexOfController:controller];
    if (index != NSNotFound) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSMutableArray *accounts = [NSMutableArray arrayWithArray:[defaults arrayForKey:UserDefaultsKeys.accounts]];
        NSMutableDictionary *account = [NSMutableDictionary dictionaryWithDictionary:accounts[index]];
        account[AKSIPAccountKeys.username] = controller.account.username;
        accounts[index] = account;
        [defaults setObject:accounts forKey:UserDefaultsKeys.accounts];
        [self.preferencesController reloadAccountAtIndex:index];
    }
}

#pragma mark - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
 didReceiveNotificationResponse:(UNNotificationResponse *)response
          withCompletionHandler:(void (^)(void))completionHandler {
    NSString *identifier = response.notification.request.identifier;
    CallController *controller = [self.accountControllers callControllerByIdentifier:identifier];

    if ([response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier]) {
        [controller showWindow:self];
        [center removeDeliveredNotificationsWithIdentifiers:@[identifier]];
    } else if ([response.actionIdentifier isEqualToString:@"answer"]) {
        [controller acceptCall];
    } else if ([response.actionIdentifier isEqualToString:@"decline"]) {
        [controller hangUpCall];
    }

    completionHandler();
}

- (void)configureUserNotifications {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;

    UNNotificationAction *answer =
        [UNNotificationAction actionWithIdentifier:@"answer"
                                             title:NSLocalizedString(@"Answer", @"Call answer button.")
                                           options:UNNotificationActionOptionForeground];
    UNNotificationAction *decline =
        [UNNotificationAction actionWithIdentifier:@"decline"
                                             title:NSLocalizedString(@"Decline", @"Call decline button.")
                                           options:UNNotificationActionOptionDestructive];
    UNNotificationCategory *incomingCall =
        [UNNotificationCategory categoryWithIdentifier:@"incoming-call"
                                               actions:@[answer, decline]
                                     intentIdentifiers:@[]
                                               options:UNNotificationCategoryOptionCustomDismissAction];
    [center setNotificationCategories:[NSSet setWithObject:incomingCall]];

    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus != UNAuthorizationStatusNotDetermined) {
            return;
        }
        [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert
                              completionHandler:^(BOOL granted, NSError *error) {
            if (error != nil) {
                NSLog(@"Could not request notification authorization: %@", error);
            }
        }];
    }];
}


#pragma mark -
#pragma mark NSWorkspace notifications

- (void)workspaceWillSleep:(NSNotification *)notification {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(handleNetworkPathChange)
                                               object:nil];
    if (self.userAgent.isStarted) {
        [self stopUserAgentAndWait];
    }
}

- (void)workspaceDidWake:(NSNotification *)notification {
    if (self.isUserSessionActive && self.networkReachability.isReachable) {
        [self.accountControllers registerAllAccounts];
    }
}

- (void)workspaceSessionDidResignActive:(NSNotification *)notification {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(handleNetworkPathChange)
                                               object:nil];
    self.userSessionActive = NO;
    [self.accountControllers unregisterAllAccounts];
}

- (void)workspaceSessionDidBecomeActive:(NSNotification *)notification {
    self.userSessionActive = YES;
    if (self.networkReachability.isReachable) {
        [self.accountControllers registerAllAccounts];
    }
}


#pragma mark - Network path changes

- (void)networkPathDidChange:(NSNotification *)notification {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(handleNetworkPathChange)
                                               object:nil];

    if (!self.networkReachability.isReachable ||
        !self.isFinishedLaunching ||
        !self.isUserSessionActive) {
        return;
    }

    // NWPathMonitor can emit several updates for one Wi-Fi, Ethernet, or VPN
    // transition. Coalesce the burst so PJSIP handles one stable path change.
    [self performSelector:@selector(handleNetworkPathChange)
               withObject:nil
               afterDelay:kNetworkPathChangeCoalescingDelay];
}

- (void)handleNetworkPathChange {
    if (!self.networkReachability.isReachable ||
        !self.isFinishedLaunching ||
        !self.isUserSessionActive) {
        return;
    }

    if (self.userAgent.isStarted) {
        [self.userAgent handleIPAddressChange];
    } else {
        [self.accountControllers registerAllAccounts];
    }
}


#pragma mark -
#pragma mark Service Provider

- (void)makeCallFromTextService:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
    if ([pboard canReadObjectForClasses:@[[NSString class]] options:@{}]) {
        [self makeCallOrRememberDestination:[pboard stringForType:NSPasteboardTypeString]];
    } else {
        NSLog(@"Could not make call, pboard couldn't give string.");
    }
}

#pragma mark -

- (void)makeCallAfterLaunchIfNeeded {
    if (self.destinationToCall.length > 0) {
        [self makeCallTo:self.destinationToCall];
        self.destinationToCall = @"";
    }
}

- (void)makeCallOrRememberDestination:(NSString *)destination {
    if (self.isFinishedLaunching) {
        [self makeCallTo:destination];
    } else {
        self.destinationToCall = destination;
    }
}

- (void)makeCallTo:(NSString *)destination {
    if ([self canMakeCall]) {
        [self.accountControllers.enabled.firstObject makeCallToDestinationRegisteringAccountIfNeeded:
         [[SanitizedCallDestination alloc] initWithString:destination]];
    }
}

- (BOOL)canMakeCall {
    return !self.applicationDialogController.isPresenting &&
        self.accountControllers.enabled.count > 0;
}

#pragma mark - NameServersChangeEventTarget

- (void)nameServersDidChange:(NameServers *)nameServers {
    NSArray *servers = nameServers.all;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:UserDefaultsKeys.useDNSSRV] &&
        servers.count > 0 &&
        ![self.userAgent.nameServers isEqualToArray:servers]) {

        self.userAgent.nameServers = servers;
        [self restartUserAgentAfterDelayOrMarkForRestart];
    }
}

@end
