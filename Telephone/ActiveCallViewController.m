//
//  ActiveCallViewController.m
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

#import "ActiveCallViewController.h"

#import "AKNSWindow+Resizing.h"
#import "AKSIPCall.h"

#import "CallController.h"
#import "CallTransferController.h"
#import "EndedCallViewController.h"


@interface ActiveCallViewController () <NSMenuItemValidation>

@property(nonatomic, getter=isShowingProgress) BOOL showingProgress;

@property(nonatomic, weak) IBOutlet NSTextField *displayedNameField;
@property(nonatomic, weak) IBOutlet NSTextField *statusField;

@property(nonatomic) IBOutlet NSProgressIndicator *callProgressIndicator;
@property(nonatomic) IBOutlet NSButton *hangUpButton;
@property(nonatomic) NSButton *muteButton;
@property(nonatomic) NSButton *holdButton;
@property(nonatomic) NSButton *transferButton;

@end

@implementation ActiveCallViewController

- (instancetype)initWithNibName:(NSString *)nibName callController:(CallController *)callController {
    self = [super initWithNibName:nibName bundle:nil];
    
    if (self != nil) {
        _enteredDTMF = [[NSMutableString alloc] init];
        [self setCallController:callController];
    }
    return self;
}

- (instancetype)init {
    NSString *reason = @"Initialize ActiveCallViewController with initWithCallController:";
    @throw [NSException exceptionWithName:@"AKBadInitCall" reason:reason userInfo:nil];
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self configureCallControls];
    [self updateCallControls];
}

- (void)configureCallControls {
    self.hangUpButton.hidden = NO;
    self.hangUpButton.image = [NSImage imageWithSystemSymbolName:@"phone.down.fill"
                                        accessibilityDescription:NSLocalizedString(@"End Call", @"End call button.")];
    self.hangUpButton.imagePosition = NSImageOnly;
    self.hangUpButton.toolTip = NSLocalizedString(@"End Call", @"End call button.");

    for (NSLayoutConstraint *constraint in self.hangUpButton.constraints) {
        if (constraint.firstAttribute == NSLayoutAttributeWidth ||
            constraint.firstAttribute == NSLayoutAttributeHeight) {
            constraint.constant = 28;
        }
    }

    NSLayoutConstraint *progressTrailingConstraint = nil;
    for (NSLayoutConstraint *constraint in self.view.constraints) {
        if (constraint.firstItem == self.view &&
            constraint.firstAttribute == NSLayoutAttributeTrailing &&
            constraint.secondItem == self.callProgressIndicator &&
            constraint.secondAttribute == NSLayoutAttributeTrailing) {
            progressTrailingConstraint = constraint;
            break;
        }
    }
    progressTrailingConstraint.active = NO;

    [self.callProgressIndicator.trailingAnchor
        constraintEqualToAnchor:self.hangUpButton.leadingAnchor
                       constant:-8].active = YES;

    self.muteButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"mic.fill"
                                                          accessibilityDescription:nil]
                                         target:self
                                         action:@selector(toggleMicrophoneMute:)];
    self.holdButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"pause.fill"
                                                          accessibilityDescription:nil]
                                         target:self
                                         action:@selector(toggleCallHold:)];
    self.transferButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.right"
                                                              accessibilityDescription:nil]
                                             target:self
                                             action:@selector(showCallTransferSheet:)];

    for (NSButton *button in @[self.muteButton, self.holdButton, self.transferButton]) {
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.bezelStyle = NSBezelStyleTexturedRounded;
        button.imagePosition = NSImageOnly;
        [self.view addSubview:button];
    }
    self.muteButton.buttonType = NSButtonTypeToggle;
    self.holdButton.buttonType = NSButtonTypeToggle;

    [NSLayoutConstraint activateConstraints:@[
        [self.transferButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.transferButton.centerYAnchor constraintEqualToAnchor:self.statusField.centerYAnchor],
        [self.transferButton.widthAnchor constraintEqualToConstant:28],
        [self.transferButton.heightAnchor constraintEqualToConstant:28],
        [self.holdButton.trailingAnchor constraintEqualToAnchor:self.transferButton.leadingAnchor constant:-8],
        [self.holdButton.centerYAnchor constraintEqualToAnchor:self.statusField.centerYAnchor],
        [self.holdButton.widthAnchor constraintEqualToConstant:28],
        [self.holdButton.heightAnchor constraintEqualToConstant:28],
        [self.muteButton.trailingAnchor constraintEqualToAnchor:self.holdButton.leadingAnchor constant:-8],
        [self.muteButton.centerYAnchor constraintEqualToAnchor:self.statusField.centerYAnchor],
        [self.muteButton.widthAnchor constraintEqualToConstant:28],
        [self.muteButton.heightAnchor constraintEqualToConstant:28],
        [self.muteButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.statusField.trailingAnchor constant:8]
    ]];
}

- (void)removeObservations {
    [[self displayedNameField] unbind:NSValueBinding];
    [[self statusField] unbind:NSValueBinding];
 }

- (IBAction)hangUpCall:(id)sender {
    [[self callController] hangUpCall];
}

- (IBAction)toggleCallHold:(id)sender {
    BOOL held = self.callController.call.isOnLocalHold;
    [self.callController setCallHeld:!held];
    [self updateCallControls];
}

- (IBAction)toggleMicrophoneMute:(id)sender {
    BOOL muted = self.callController.call.isMicrophoneMuted;
    [self.callController setMicrophoneMuted:!muted];
    [self updateCallControls];
}

- (IBAction)showCallTransferSheet:(id)sender {
    if (![[self callController] isCallOnHold]) {
        [[self callController] setCallHeld:YES];
    }
    
    CallTransferController *callTransferController = [[self callController] callTransferController];

    [[[self callController] window] beginSheet:[callTransferController window] completionHandler:nil];
}

- (void)startCallTimer {
    if ([self callTimer] != nil && [[self callTimer] isValid]) {
        return;
    }
    
    [self setCallTimer:
     [NSTimer scheduledTimerWithTimeInterval:0.2
                                      target:self
                                    selector:@selector(callTimerTick:)
                                    userInfo:nil
                                     repeats:YES]];
}

- (void)stopCallTimer {
    if ([self callTimer] != nil) {
        [[self callTimer] invalidate];
        [self setCallTimer:nil];
    }
}

- (void)callTimerTick:(NSTimer *)theTimer {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSInteger seconds = (NSInteger)(now - ([[self callController] callStartTime]));
    
    if (seconds < 3600) {
        [[self callController] setStatus:[NSString stringWithFormat:@"%02ld:%02ld",
                                          (seconds / 60) % 60, seconds % 60]];
    } else {
        [[self callController]
         setStatus:[NSString stringWithFormat:@"%02ld:%02ld:%02ld",
                    (seconds / 3600) % 24, (seconds / 60) % 60, seconds % 60]];
    }
}

- (void)showProgress {
    if (!self.isShowingProgress) {
        [self.callProgressIndicator startAnimation:self];
        self.showingProgress = YES;
    }
    self.callProgressIndicator.hidden = NO;
    self.hangUpButton.hidden = NO;
    [self updateCallControls];
}

- (void)showHangUp {
    if (self.isShowingProgress) {
        [self.callProgressIndicator stopAnimation:nil];
        self.showingProgress = NO;
    }
    self.callProgressIndicator.hidden = YES;
    self.hangUpButton.hidden = NO;
    [self updateCallControls];
}

- (void)allowHangUp {
    self.hangUpButton.enabled = YES;
}

- (void)disallowHangUp {
    self.hangUpButton.enabled = NO;
}

- (void)updateCallControls {
    AKSIPCall *call = self.callController.call;
    BOOL confirmed = call.state == kAKSIPCallConfirmedState;

    BOOL muted = call.isMicrophoneMuted;
    self.muteButton.enabled = confirmed;
    self.muteButton.state = muted ? NSControlStateValueOn : NSControlStateValueOff;
    self.muteButton.image = [NSImage imageWithSystemSymbolName:(muted ? @"mic.slash.fill" : @"mic.fill")
                                      accessibilityDescription:nil];
    NSString *muteTitle = muted
        ? NSLocalizedString(@"Unmute", @"Unmute. Call menu item.")
        : NSLocalizedString(@"Mute", @"Mute. Call menu item.");
    self.muteButton.toolTip = muteTitle;
    self.muteButton.accessibilityLabel = muteTitle;

    BOOL held = call.isOnLocalHold;
    self.holdButton.enabled = confirmed && !call.isOnRemoteHold;
    self.holdButton.state = held ? NSControlStateValueOn : NSControlStateValueOff;
    self.holdButton.image = [NSImage imageWithSystemSymbolName:(held ? @"play.fill" : @"pause.fill")
                                      accessibilityDescription:nil];
    NSString *holdTitle = held
        ? NSLocalizedString(@"Resume", @"Resume. Call menu item.")
        : NSLocalizedString(@"Hold", @"Hold. Call menu item.");
    self.holdButton.toolTip = holdTitle;
    self.holdButton.accessibilityLabel = holdTitle;

    BOOL transferEnabled = confirmed && !call.isOnRemoteHold;
    NSString *transferTitle = NSLocalizedString(@"Transfer", @"Transfer. Call menu item.");
    self.transferButton.enabled = transferEnabled;
    self.transferButton.toolTip = transferTitle;
    self.transferButton.accessibilityLabel = transferTitle;
}


#pragma mark -
#pragma mark AKActiveCallViewDelegate protocol

- (void)activeCallView:(AKActiveCallView *)sender didReceiveText:(NSString *)aString {
    NSCharacterSet *DTMFCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789*#abcdrABCDR"];
    
    BOOL isDTMFValid = YES;
    for (NSUInteger i = 0; i < [aString length]; ++i) {
        unichar digit = [aString characterAtIndex:i];
        if (![DTMFCharacterSet characterIsMember:digit]) {
            isDTMFValid = NO;
            break;
        }
    }
    
    if (isDTMFValid) {
        if ([[self enteredDTMF] length] == 0) {
            [[self enteredDTMF] appendString:aString];
            [[[self view] window] setTitle:[[self callController] displayedName]];
            
            if ([[self displayedNameField] lineBreakMode]!= NSLineBreakByTruncatingHead) {
                [[self displayedNameField] setLineBreakMode:NSLineBreakByTruncatingHead];
                [[[[self callController] endedCallViewController] displayedNameField] setSelectable:YES];
            }
            
            [[self callController] setDisplayedName:aString];
            
        } else {
            [[self enteredDTMF] appendString:aString];
            [[self callController] setDisplayedName:[self enteredDTMF]];
        }
        
        [[[self callController] call] sendDTMFDigits:aString];
    }
}


#pragma mark -
#pragma mark NSMenuItemValidation protocol

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem action] == @selector(toggleMicrophoneMute:)) {
        if ([[[self callController] call] isMicrophoneMuted]) {
            [menuItem setTitle:NSLocalizedString(@"Unmute", @"Unmute. Call menu item.")];
        } else {
            [menuItem setTitle:NSLocalizedString(@"Mute", @"Mute. Call menu item.")];
        }
        
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState) {
            return YES;
        } else {
            return NO;
        }
        
    } else if ([menuItem action] == @selector(toggleCallHold:)) {
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState &&
            [[[self callController] call] isOnLocalHold]) {
            [menuItem setTitle:NSLocalizedString(@"Resume", @"Resume. Call menu item.")];
        } else {
            [menuItem setTitle:NSLocalizedString(@"Hold", @"Hold. Call menu item.")];
        }
        
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState &&
            ![[[self callController] call] isOnRemoteHold]) {
            
            return YES;
            
        } else {
            return NO;
        }
        
    } else if ([menuItem action] == @selector(showCallTransferSheet:)) {
        if ([[[self callController] call] state] == kAKSIPCallConfirmedState &&
            ![[[self callController] call] isOnRemoteHold]) {
            
            return YES;
            
        } else {
            return NO;
        }
        
    } else if ([menuItem action] == @selector(hangUpCall:)) {
        [menuItem setTitle:NSLocalizedString(@"End Call", @"End Call. Call menu item.")];

        return self.hangUpButton.isEnabled;
    }
    
    return YES;
}

@end
