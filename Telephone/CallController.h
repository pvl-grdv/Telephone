//
//  CallController.h
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

#import <Foundation/Foundation.h>

#import "AKSIPCall.h"

#import "CallControllerDelegate.h"


@class AccountController, AKSIPCall, AKSIPURI, AKSIPUserAgent;
@class CallTransferController;

NS_ASSUME_NONNULL_BEGIN

// A call controller.
@interface CallController : NSObject <AKSIPCallDelegate>

@property(nonatomic, readonly, weak, nullable) id<CallControllerDelegate> delegate;

// The receiver's identifier.
@property(nonatomic, copy) NSString * _Nonnull identifier;

// Call controlled by the receiver.
@property(nonatomic, strong, nullable) AKSIPCall *call;

// Account controller the receiver belongs to.
@property(nonatomic, weak, nullable) AccountController *accountController;

// Call transfer controller.
@property(nonatomic, readonly, nullable) CallTransferController *callTransferController;


@property(nonatomic, copy, nullable) NSString *title;

// Remote party dislpay name.
@property(nonatomic, copy, nullable) NSString *displayedName;

// Call status.
@property(nonatomic, copy, nullable) NSString *status;

// Remote party name from the Address Book.
@property(nonatomic, copy, nullable) NSString *nameFromAddressBook;

// Remote party label from the Address Book.
@property(nonatomic, copy, nullable) NSString *phoneLabelFromAddressBook;

// Call destination entered by a user.
@property(nonatomic, copy, nullable) NSString *enteredCallDestination;

// SIP URI for the redial.
@property(nonatomic, copy, nullable) AKSIPURI *redialURI;

// Timer to display intermediate call status. This status appears for the short period of time and then is being
// replaced with the current call status.
@property(nonatomic, strong, nullable) NSTimer *intermediateStatusTimer;

// Call start time.
@property(nonatomic, assign) NSTimeInterval callStartTime;

// A Boolean value indicating whether the receiver's call is on hold.
@property(nonatomic, assign, getter=isCallOnHold) BOOL callOnHold;

// A Boolean value indicating whether the receiver's call is active.
@property(nonatomic, assign, getter=isCallActive) BOOL callActive;

// A Boolean value indicating whether the receiver's call is unhandled.
@property(nonatomic, readonly, getter=isCallUnhandled) BOOL callUnhandled;


- (instancetype)initWithWindowNibName:(NSString *)windowNibName
                    accountController:(AccountController *)accountController
                            userAgent:(AKSIPUserAgent *)userAgent
                             delegate:(id<CallControllerDelegate>)delegate;

- (void)showWindow:(nullable id)sender;
- (void)close;
- (void)callWindowDidClose;

// Accepts an incoming call.
- (void)acceptCall;

// Hangs up a call.
- (void)hangUpCall;

// Redials a call.
- (void)redial;

// Sets and toggles call hold.
- (void)setCallHeld:(BOOL)held;
- (void)toggleCallHold;

// Sets and toggles microphone mute.
- (void)setMicrophoneMuted:(BOOL)muted;
- (void)toggleMicrophoneMute;

// Sets intermediate call status. This status appears for the short period of time and then is being replaced with the
// current call status.
- (void)setIntermediateStatus:(NSString * _Nonnull)newIntermediateStatus;

// Method to be called when intermediate call status timer fires.
- (void)intermediateStatusTimerTick:(NSTimer * _Nonnull)theTimer;

- (void)prepareForCall;
- (void)showEndedCallView;
- (void)showIncomingCallView;

@end

NS_ASSUME_NONNULL_END
