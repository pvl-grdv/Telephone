//
//  PreferencesController.m
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

#import "PreferencesController.h"

#import "Telephone-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface PreferencesController () <NSWindowDelegate>

@property(nonatomic, readonly) SettingsViewController *settingsViewController;

@end

NS_ASSUME_NONNULL_END

@implementation PreferencesController

- (void)setDelegate:(id)aDelegate {
    if (_delegate == aDelegate) {
        return;
    }

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    if (_delegate != nil) {
        [center removeObserver:_delegate name:nil object:self];
    }

    if (aDelegate != nil) {
        if ([aDelegate respondsToSelector:@selector(preferencesControllerDidRemoveAccount:)]) {
            [center addObserver:aDelegate
                      selector:@selector(preferencesControllerDidRemoveAccount:)
                          name:AKPreferencesControllerDidRemoveAccountNotification
                        object:self];
        }

        if ([aDelegate respondsToSelector:@selector(preferencesControllerDidChangeAccountEnabled:)]) {
            [center addObserver:aDelegate
                      selector:@selector(preferencesControllerDidChangeAccountEnabled:)
                          name:AKPreferencesControllerDidChangeAccountEnabledNotification
                        object:self];
        }

        if ([aDelegate respondsToSelector:@selector(preferencesControllerDidSwapAccounts:)]) {
            [center addObserver:aDelegate
                      selector:@selector(preferencesControllerDidSwapAccounts:)
                          name:AKPreferencesControllerDidSwapAccountsNotification
                        object:self];
        }

        if ([aDelegate respondsToSelector:@selector(preferencesControllerDidChangeNetworkSettings:)]) {
            [center addObserver:aDelegate
                      selector:@selector(preferencesControllerDidChangeNetworkSettings:)
                          name:AKPreferencesControllerDidChangeNetworkSettingsNotification
                        object:self];
        }
    }

    _delegate = aDelegate;
}

- (instancetype)initWithDelegate:(id<PreferencesControllerDelegate>)delegate
                       userAgent:(AKSIPUserAgent *)userAgent
 soundPreferencesViewEventTarget:(SoundPreferencesViewEventTarget *)soundPreferencesViewEventTarget {
    self = [super initWithWindow:nil];
    if (self == nil) {
        return nil;
    }

    self.delegate = delegate;
    _userAgent = userAgent;
    _soundPreferencesViewEventTarget = soundPreferencesViewEventTarget;

    _settingsViewController =
        [[SettingsViewController alloc]
            initWithSoundEventTarget:soundPreferencesViewEventTarget
                           userAgent:userAgent
               preferencesController:self];

    NSWindow *window =
        [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 720, 560)
                                    styleMask:NSWindowStyleMaskTitled |
                                              NSWindowStyleMaskClosable
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    window.title = NSLocalizedString(@"Telephone Settings", @"Settings default window title.");
    window.releasedWhenClosed = NO;
    window.contentViewController = _settingsViewController;
    window.delegate = self;
    self.window = window;

    return self;
}

- (void)dealloc {
    [self setDelegate:nil];
}

- (void)showWindowCentered {
    if (!self.window.isVisible) {
        [self.window center];
    }
    [self showWindow:self];
}

- (void)showAccounts {
    [self.settingsViewController showAccounts];
}

- (void)reloadAccountAtIndex:(NSInteger)index {
    [self.settingsViewController reloadAccountAt:index];
}

#pragma mark - SoundIOPreferences

- (void)updateSoundIO {
    [self.settingsViewController updateSoundIO];
}

#pragma mark - NSWindowDelegate

- (BOOL)windowShouldClose:(NSWindow *)sender {
    return [self.settingsViewController requestWindowClose];
}

@end
