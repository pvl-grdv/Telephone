//
//  CallController.m
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

#import "CallController.h"

@import UserNotifications;
@import UseCases;

#import "AKSIPURI.h"
#import "AKSIPURIFormatter.h"
#import "AKSIPUserAgent.h"
#import "AKTelephoneNumberFormatter.h"

#import "AccountController.h"
#import "AppController.h"
#import "CallController+Protected.h"
#import "CallTransferController.h"
#import "SIPResponseLocalization.h"

#import "Telephone-Swift.h"


// Window auto-close delay.
static const NSTimeInterval kCallWindowAutoCloseTime = 1.5;

// Redial button re-enable delay.
static const NSTimeInterval kRedialButtonReenableTime = 1.0;

@interface CallController ()

@property(nonatomic, readonly) AKSIPUserAgent *userAgent;

@property(nonatomic, readonly) NSUserDefaults *defaults;

// SwiftUI container used by call and call-transfer windows.
@property(nonatomic, strong) CallContentViewController *callContentViewController;

- (void)configureWindowBehavior;
- (void)configureSwiftCallWindowForTransfer:(BOOL)isTransfer;

// Closes call window.
- (void)closeCallWindow;

@end

@implementation CallController

@synthesize callTransferController = _callTransferController;

- (void)setCall:(AKSIPCall *)call {
    if (_call != call) {
        if (_call.delegate == self) {
            _call.delegate = nil;
        }
        _call = call;
        _call.delegate = self;
        [self.callContentViewController setCall:_call];
        if (_call != nil) {
            self.window.styleMask |= NSWindowStyleMaskClosable;
            [self.callContentViewController setHangUpEnabled:YES];

            // Keep the remote party identity available in every call state.
            // AccountController normally sets these before the call starts,
            // but the SIP call itself is the reliable fallback for paths such
            // as restored/redialed calls and late UI transitions.
            AKSIPURIFormatter *formatter = [[AKSIPURIFormatter alloc] init];
            formatter.formatsTelephoneNumbers =
                [self.defaults boolForKey:UserDefaultsKeys.formatTelephoneNumbers];
            formatter.telephoneNumberFormatterSplitsLastFourDigits =
                [self.defaults boolForKey:UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits];
            NSString *remoteIdentity = [formatter stringForObjectValue:_call.remoteURI];
            NSString *remoteAddress = _call.remoteURI.SIPAddress;
            if (remoteAddress.length == 0) {
                remoteAddress = remoteIdentity;
            }

            if (self.title.length == 0) {
                self.title = remoteAddress;
            }
            if (self.displayedName.length == 0) {
                self.displayedName = remoteIdentity ?: remoteAddress;
            }
        }
    }
}

- (CallTransferController *)callTransferController {
    if (_callTransferController == nil) {
        _callTransferController = [[CallTransferController alloc] initWithSourceCallController:self userAgent:self.userAgent];
    }
    return _callTransferController;
}


- (void)setTitle:(NSString *)title {
    if (![_title isEqualToString:title]) {
        _title = [title copy];
        if (self.isWindowLoaded) {
            [self updateWindowTitle];
        }
    }
}

- (void)setDisplayedName:(NSString *)displayedName {
    if (![_displayedName isEqualToString:displayedName]) {
        _displayedName = [displayedName copy];
        [self.callContentViewController setDisplayedName:_displayedName ?: @""];
    }
}

- (void)setStatus:(NSString *)status {
    if (![_status isEqualToString:status]) {
        _status = [status copy];
        [self.callContentViewController setStatus:_status ?: @""];
    }
}

- (BOOL)isCallUnhandled {
    return self.call.isMissed;
}

- (instancetype)initWithWindowNibName:(NSString *)windowNibName
                    accountController:(AccountController *)accountController
                            userAgent:(AKSIPUserAgent *)userAgent
                             delegate:(id<CallControllerDelegate>)delegate {

    BOOL isTransfer = [windowNibName isEqualToString:@"CallTransfer"];
    BOOL usesSwiftCallWindow = [windowNibName isEqualToString:@"Call"] || isTransfer;
    NSAssert(usesSwiftCallWindow, @"Unsupported call window: %@", windowNibName);

    self = [super initWithWindow:nil];

    if (self != nil) {
        _identifier = [NSUUID UUID].UUIDString;
        _accountController = accountController;
        _userAgent = userAgent;
        _delegate = delegate;
        _defaults = NSUserDefaults.standardUserDefaults;

        [self configureSwiftCallWindowForTransfer:isTransfer];
    }
    return self;
}

- (void)dealloc {
    [self setCall:nil];
    [self unsubscribeFromWindowFloatingChanges];
}

- (NSString *)description {
    return [[self call] description];
}

- (void)configureWindowBehavior {
    self.window.movableByWindowBackground = YES;
    [self updateWindowFloating];
    [self subscribeToWindowFloatingChanges];
    [self updateWindowTitle];
}

- (void)configureSwiftCallWindowForTransfer:(BOOL)isTransfer {
    self.callContentViewController =
        [[CallContentViewController alloc] initWithCallController:self
                                                accountController:self.accountController
                                                      isTransfer:isTransfer];

    NSSize contentSize = isTransfer ? NSMakeSize(360, 160) : NSMakeSize(420, 318);
    NSWindowStyleMask styleMask =
        NSWindowStyleMaskTitled |
        NSWindowStyleMaskClosable |
        NSWindowStyleMaskMiniaturizable;
    if (!isTransfer) {
        styleMask |= NSWindowStyleMaskResizable;
    }

    NSWindow *window =
        [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, contentSize.width, contentSize.height)
                                    styleMask:styleMask
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    window.animationBehavior = NSWindowAnimationBehaviorDefault;
    window.titlebarAppearsTransparent = !isTransfer;
    window.releasedWhenClosed = NO;
    window.delegate = self;
    window.contentViewController = self.callContentViewController;
    if (!isTransfer) {
        window.contentMinSize = NSMakeSize(380, 280);
    }

    if (isTransfer) {
        self.title = NSLocalizedString(@"Call Transfer", @"Call transfer window title.");
    } else {
        [window setFrameAutosaveName:@"Call"];
    }

    self.window = window;
    [self configureWindowBehavior];
}

- (void)acceptCall {
    [[self call] answer];
    [self removeUserNotification];
}

- (void)hangUpCall {
    [self setCallActive:NO];

    [self.callContentViewController stopCallTimer];
    
    // If remote party hasn't sent back any replies, call hang-up will not happen immediately. Unsubscribe from any
    // notifications about the call state and set disconnected look to the call window.
    
    if ([[[self call] delegate] isEqual:self]) {
        [[self call] setDelegate:nil];
    }
    
    [[self call] hangUp];
    
    [self setStatus:NSLocalizedString(@"call ended", @"Call ended.")];

    [self showEndedCallView];
    
    [self.callContentViewController setProgressVisible:NO];
    [self.callContentViewController setHangUpEnabled:NO];
    [self.callContentViewController setIncomingActionsEnabled:NO];
    
    [self removeUserNotification];

    // Optionally close call window.
    if ([self.defaults boolForKey:UserDefaultsKeys.autoCloseCallWindow] && ![self isKindOfClass:[CallTransferController class]]) {
        [self performSelector:@selector(closeCallWindow) withObject:nil afterDelay:kCallWindowAutoCloseTime];
    }
}

- (void)redial {
    if (![[self userAgent] isStarted] ||
        ![[self accountController] isEnabled] ||
        ![[self accountController] canMakeCalls] ||
        [self redialURI] == nil) {
        
        return;
    }
    
    // Cancel call window auto-close.
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(closeCallWindow)
                                               object:nil];
    
    // Replace plus character if needed.
    if ([[self accountController] substitutesPlusCharacter] &&
        [[[self redialURI] user] hasPrefix:@"+"]) {
        
        [[self redialURI] setUser:[[[self redialURI] user]
                                   stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                   withString:[[self accountController]
                                               plusCharacterSubstitution]]];
    }

    [self prepareForCall];
    
    if ([[self phoneLabelFromAddressBook] length] > 0) {
        [self setStatus:[NSString stringWithFormat:
                         NSLocalizedString(@"calling %@...",
                                           @"Outgoing call in progress. Calling specific phone "
                                            "type (mobile, home, etc)."),
          [self phoneLabelFromAddressBook]]];
        
    } else {
        [self setStatus:NSLocalizedString(@"calling...", @"Outgoing call in progress.")];
    }

    // Make actual call.
    [self.accountController.account makeCallTo:self.redialURI completion:^(AKSIPCall *call) {
        if (call != nil) {
            [self setCall:call];
            [self setCallActive:YES];
        } else {
            [self showEndedCallView];
            [self setStatus:NSLocalizedString(@"Call Failed", @"Call failed.")];
        }
    }];
}

- (void)setCallHeld:(BOOL)held {
    if ([[self call] state] == kAKSIPCallConfirmedState && ![[self call] isOnRemoteHold]) {
        [[self call] setHeld:held];
    }
}

- (void)toggleCallHold {
    [self setCallHeld:![[self call] isOnLocalHold]];
}

- (void)setMicrophoneMuted:(BOOL)muted {
    if ([[self call] state] != kAKSIPCallConfirmedState) {
        return;
    }

    [[self call] setMuted:muted];

    if ([[self call] isMicrophoneMuted]) {
        if (![self isCallOnHold]) {
            [self.callContentViewController stopCallTimer];
            [self setStatus:NSLocalizedString(@"mic muted", @"Microphone muted status text.")];
        } else {
            [self setIntermediateStatus:NSLocalizedString(@"mic muted", @"Microphone muted status text.")];
        }
    } else {
        [self setIntermediateStatus:NSLocalizedString(@"mic unmuted", @"Microphone unmuted status text.")];
    }
}

- (void)toggleMicrophoneMute {
    [self setMicrophoneMuted:![[self call] isMicrophoneMuted]];
}

- (void)setIntermediateStatus:(NSString *)newIntermediateStatus {
    if ([self intermediateStatusTimer] != nil) {
        [[self intermediateStatusTimer] invalidate];
    }
    
    [self.callContentViewController stopCallTimer];
    [self setStatus:newIntermediateStatus];
    [self setIntermediateStatusTimer:
     [NSTimer scheduledTimerWithTimeInterval:3.0
                                      target:self
                                    selector:@selector(intermediateStatusTimerTick:)
                                    userInfo:nil
                                     repeats:NO]];
}

- (void)intermediateStatusTimerTick:(NSTimer *)theTimer {
    if ([[self call] isOnLocalHold]) {
        [self setStatus:NSLocalizedString(@"on hold", @"Call on local hold status text.")];
    } else if ([[self call] isOnRemoteHold]) {
        [self setStatus:
         NSLocalizedString(@"on remote hold", @"Call on remote hold status text.")];
    } else if ([[self call] isMicrophoneMuted]) {
        [self setStatus:
         NSLocalizedString(@"mic muted", @"Microphone muted status text.")];
    } else if ([[self call] isActive]) {
        [self.callContentViewController startCallTimer];
    }
    
    [self setIntermediateStatusTimer:nil];
}

- (void)closeCallWindow {
    if ([[self window] isVisible]) {
        [[self window] performClose:self];
    }
}

- (void)prepareForCall {
    self.window.styleMask &= ~NSWindowStyleMaskClosable;
    [self showActiveCallView];
    [self.callContentViewController setProgressVisible:YES];
    [self.callContentViewController setHangUpEnabled:NO];
}

- (void)showActiveCallView {
    [self.callContentViewController showActiveState];
}

- (void)showEndedCallView {
    self.window.styleMask |= NSWindowStyleMaskClosable;
    [self.callContentViewController showEndedState];
}

- (void)showIncomingCallView {
    [self.callContentViewController showIncomingState];
}

- (void)showTransferDestinationState {
    [self.callContentViewController showTransferDestinationState];
}

- (void)focusTransferDestination {
    [self.callContentViewController focusTransferDestination];
}

- (void)setTransferActionEnabled:(BOOL)enabled {
    [self.callContentViewController setTransferActionEnabled:enabled];
}

- (void)callDidHoldForTransfer {
    [self.callContentViewController callDidHoldForTransfer];
}

- (void)removeOrShowUserNotificationOnDisconnectIfNeeded {
    if (![NSApp isActive]) {
        if (self.isCallUnhandled) {
            // Missed calls are shown in call history.
            [self removeUserNotification];
        } else {
            // Notify about an ended call when the app is not visible.
            [self showUserNotification];
        }
    }
}

- (void)removeUserNotification {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center removeDeliveredNotificationsWithIdentifiers:@[self.identifier]];
    [center removePendingNotificationRequestsWithIdentifiers:@[self.identifier]];
}

- (void)showUserNotification {
    NSString *notificationTitle;
    if ([[self nameFromAddressBook] length] > 0) {
        notificationTitle = [self nameFromAddressBook];
    } else if ([[self enteredCallDestination] length] > 0) {
        AKTelephoneNumberFormatter *telephoneNumberFormatter = [[AKTelephoneNumberFormatter alloc] init];
        if ([[self enteredCallDestination] ak_isTelephoneNumber] && [self.defaults boolForKey:UserDefaultsKeys.formatTelephoneNumbers]) {
            notificationTitle = [telephoneNumberFormatter stringForObjectValue:[self enteredCallDestination]];
        } else {
            notificationTitle = [self enteredCallDestination];
        }
    } else {
        AKSIPURIFormatter *SIPURIFormatter = [[AKSIPURIFormatter alloc] init];
        [SIPURIFormatter setFormatsTelephoneNumbers:[self.defaults boolForKey:UserDefaultsKeys.formatTelephoneNumbers]];
        [SIPURIFormatter setTelephoneNumberFormatterSplitsLastFourDigits:
         [self.defaults boolForKey:UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits]];
        notificationTitle = [SIPURIFormatter stringForObjectValue:[[self call] remoteURI]];
    }

    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = notificationTitle ?: @"";
    content.body = self.status ?: @"";

    UNNotificationRequest *request =
        [UNNotificationRequest requestWithIdentifier:self.identifier content:content trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter]
        addNotificationRequest:request
         withCompletionHandler:^(NSError *error) {
            if (error != nil) {
                NSLog(@"Could not deliver call notification: %@", error);
            }
        }];
}

- (void)updateWindowTitle {
    self.window.title = self.title.length > 0 ? self.title : NSLocalizedString(@"Call", @"Window title.");
}


#pragma mark -
#pragma mark NSWindow delegate methods

- (void)windowWillClose:(NSNotification *)notification {
    if ([self isCallActive]) {
        [self setCallActive:NO];
        [self.callContentViewController stopCallTimer];
        
        if ([[[self call] delegate] isEqual:self]) {
            [[self call] setDelegate:nil];
        }
        
        [[self call] hangUp];
    }
    
    [self.delegate callControllerWillClose:self];

}

- (NSRect)window:(NSWindow *)window willPositionSheet:(NSWindow *)sheet usingRect:(NSRect)rect {
    rect.origin.y = [self.window contentRectForFrameRect:self.window.frame].size.height;
    return rect;
}


#pragma mark -
#pragma mark AKSIPCallDelegate

- (void)SIPCallEarly:(NSNotification *)notification {
    if (![[self call] isIncoming]) {
        NSNumber *sipEventCode = [notification userInfo][@"AKSIPEventCode"];
        if ([sipEventCode isEqualToNumber:@(PJSIP_SC_RINGING)]) {
            [self.callContentViewController setProgressVisible:NO];
            [self setStatus:NSLocalizedString(@"ringing", @"Remote party ringing.")];
        }
    }
}

- (void)SIPCallDidConfirm:(NSNotification *)notification {
    [self removeUserNotification];
    [self setCallStartTime:[NSDate timeIntervalSinceReferenceDate]];
    [self showActiveCallView];
    [self.callContentViewController setProgressVisible:NO];
    [self.callContentViewController updateCallControls];
    [self setStatus:@"00:00"];
    [self.callContentViewController startCallTimer];
}

- (void)SIPCallDidDisconnect:(NSNotification *)notification {
    [self setCallActive:NO];
    [self.callContentViewController stopCallTimer];
    
    NSString *preferredLocalization = [[NSBundle mainBundle] preferredLocalizations][0];
    
    switch ([[self call] lastStatus]) {
        case PJSIP_SC_OK:
            [self setStatus:NSLocalizedString(@"call ended", @"Call ended.")];
            break;
            
        case PJSIP_SC_NOT_FOUND:
            [self setStatus:NSLocalizedString(@"Address Not Found", @"Address not found.")];
            break;
            
        case PJSIP_SC_REQUEST_TERMINATED:
            [self setStatus:NSLocalizedString(@"call ended", @"Call ended.")];
            break;
            
        case PJSIP_SC_BUSY_HERE:
        case PJSIP_SC_BUSY_EVERYWHERE:
            [self setStatus:NSLocalizedString(@"busy", @"Busy.")];
            break;
            
        case PJSIP_SC_DECLINE:
            [self setStatus:NSLocalizedString(@"call declined", @"Call declined.")];
            break;
            
        default:
            if ([preferredLocalization isEqualToString:@"ru"]) {
                NSString *statusText = LocalizedStringForSIPResponseCode([[self call] lastStatus]);
                if (statusText == nil) {
                    [self setStatus:[NSString stringWithFormat:NSLocalizedString(@"Error %ld", @"Error #."),
                                     [[self call] lastStatus]]];
                } else {
                    [self setStatus:statusText];
                }
            } else {
                [self setStatus:[[self call] lastStatusText]];
            }
            break;
    }

    [self showEndedCallView];
    
    // Disable the redial button to re-enable it after some delay to prevent accidental clicking on in instead of
    // clicking on the hang-up button. Don't forget to re-enable it below!
    [self.callContentViewController setRedialEnabled:NO];
    
    [self.callContentViewController setProgressVisible:NO];
    [self.callContentViewController setHangUpEnabled:NO];
    [self.callContentViewController setIncomingActionsEnabled:NO];
    
    [NSTimer scheduledTimerWithTimeInterval:kRedialButtonReenableTime
                                     target:self.callContentViewController
                                   selector:@selector(enableRedialButtonTick:)
                                   userInfo:nil
                                    repeats:NO];
    
    [self removeOrShowUserNotificationOnDisconnectIfNeeded];
    
    // Optionally close disconnected call window.
    BOOL shouldCloseWindow = [self.defaults boolForKey:UserDefaultsKeys.autoCloseCallWindow];
    BOOL shouldCloseMissedWindow = [self.defaults boolForKey:UserDefaultsKeys.autoCloseMissedCallWindow];
    BOOL missed = [self isCallUnhandled];
    
    if (![self isKindOfClass:[CallTransferController class]]) {
        if ((!missed && shouldCloseWindow) || (missed && shouldCloseMissedWindow)) {
            [self performSelector:@selector(closeCallWindow) withObject:nil afterDelay:kCallWindowAutoCloseTime];
        }
    }
}

- (void)SIPCallMediaDidBecomeActive:(NSNotification *)notification {
    [self.callContentViewController updateCallControls];
    if ([self isCallOnHold]) {  // Call is being taken off hold.
        [self setCallOnHold:NO];
        
        [self setIntermediateStatus:NSLocalizedString(@"off hold", @"Call has been taken off hold status text.")];
    }
}

- (void)SIPCallDidLocalHold:(NSNotification *)notification {
    [self setCallOnHold:YES];
    [self.callContentViewController updateCallControls];
    [self.callContentViewController stopCallTimer];
    [self setStatus:NSLocalizedString(@"on hold", @"Call on local hold status text.")];
}

- (void)SIPCallDidRemoteHold:(NSNotification *)notification {
    [self setCallOnHold:YES];
    [self.callContentViewController updateCallControls];
    [self.callContentViewController stopCallTimer];
    [self setStatus:NSLocalizedString(@"on remote hold", @"Call on remote hold status text.")];
}

- (void)SIPCallTransferStatusDidChange:(NSNotification *)notification {
    NSDictionary *userInfo = [notification userInfo];
    BOOL isFinal = [userInfo[@"AKFinalTransferNotification"] boolValue];
    
    if (isFinal && [[self call] transferStatus] == PJSIP_SC_OK) {
        [self hangUpCall];
        [self setStatus:NSLocalizedString(@"call transferred", @"Call transferred.")];
    }
}

#pragma mark - Window floating

- (void)updateWindowFloating {
    self.window.level = [self.defaults boolForKey:UserDefaultsKeys.keepCallWindowOnTop] ? NSFloatingWindowLevel : NSNormalWindowLevel;
}

- (void)subscribeToWindowFloatingChanges {
    [self.defaults addObserver:self forKeyPath:UserDefaultsKeys.keepCallWindowOnTop options:0 context:NULL];
}

- (void)unsubscribeFromWindowFloatingChanges {
    [self.defaults removeObserver:self forKeyPath:UserDefaultsKeys.keepCallWindowOnTop];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (object == self.defaults && [keyPath isEqualToString:UserDefaultsKeys.keepCallWindowOnTop]) {
        [self updateWindowFloating];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end
