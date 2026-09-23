//
//  CallTransferController.m
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

#import "CallTransferController.h"

#import "AKSIPCall.h"

#import "AccountController.h"
#import "CallController+Protected.h"


@interface CallTransferController ()

@property(nonatomic, weak) CallController *sourceCallController;
@property(nonatomic, assign) BOOL sourceCallTransferred;

@end


@implementation CallTransferController

- (void)setSourceCallController:(CallController *)callController {
    if (_sourceCallController == callController) {
        return;
    }

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    if (_sourceCallController != nil) {
        [center removeObserver:self
                         name:AKSIPCallTransferStatusDidChangeNotification
                       object:[_sourceCallController call]];
    }

    if (callController != nil) {
        [center addObserver:self
                   selector:@selector(sourceCallControllerSIPCallTransferStatusDidChange:)
                       name:AKSIPCallTransferStatusDidChangeNotification
                     object:[callController call]];
    }

    self.sourceCallTransferred = NO;
    _sourceCallController = callController;
}

- (instancetype)initWithSourceCallController:(CallController *)callController
                                   userAgent:(AKSIPUserAgent *)userAgent {
    AccountController *accountController = callController.accountController;

    self = [self initWithWindowNibName:@"CallTransfer"
                    accountController:accountController
                            userAgent:userAgent
                             delegate:accountController];
    if (self == nil) {
        return nil;
    }

    [self setSourceCallController:callController];
    [self showInitialState:self];
    return self;
}

- (void)transferCall {
    [self.sourceCallController.call attendedTransferToCall:self.call];
}

- (IBAction)closeSheet:(id)sender {
    if (self.sourceCallController.isCallActive &&
        self.sourceCallController.isCallOnHold) {
        [self.sourceCallController toggleCallHold];
    }

    [self.window.sheetParent endSheet:self.window];
}

- (IBAction)showInitialState:(id)sender {
    if (self.isCallActive) {
        [self hangUpCall];
    }

    if (!self.sourceCallController.isCallActive) {
        [self closeSheet:self];
        return;
    }

    [self showTransferDestinationState];
    [self focusTransferDestination];
}


#pragma mark - CallController methods

- (CallTransferController *)callTransferController {
    return nil;
}

- (void)acceptCall {
    // Transfer destination calls are outgoing only.
}

- (void)prepareForCall {
    [super prepareForCall];
    [self setTransferActionEnabled:NO];
}


#pragma mark - AKSIPCall notifications

- (void)SIPCallEarly:(NSNotification *)notification {
    [super SIPCallEarly:notification];
    [self setTransferActionEnabled:NO];
}

- (void)SIPCallDidConfirm:(NSNotification *)notification {
    [super SIPCallDidConfirm:notification];
    [self setTransferActionEnabled:YES];
}

- (void)SIPCallDidDisconnect:(NSNotification *)notification {
    [super SIPCallDidDisconnect:notification];

    if (self.sourceCallTransferred) {
        [self closeSheet:self];
    }
}

- (void)SIPCallMediaDidBecomeActive:(NSNotification *)notification {
    [super SIPCallMediaDidBecomeActive:notification];
    [self setTransferActionEnabled:YES];
}

- (void)SIPCallDidLocalHold:(NSNotification *)notification {
    [super SIPCallDidLocalHold:notification];
    [self callDidHoldForTransfer];
}

- (void)SIPCallDidRemoteHold:(NSNotification *)notification {
    [super SIPCallDidRemoteHold:notification];
    [self setTransferActionEnabled:NO];
}


#pragma mark - Source call transfer status

- (void)sourceCallControllerSIPCallTransferStatusDidChange:(NSNotification *)notification {
    AKSIPCall *sourceCall = notification.object;
    BOOL isFinal = [notification.userInfo[@"AKFinalTransferNotification"] boolValue];

    if (isFinal && sourceCall.transferStatus == PJSIP_SC_OK) {
        self.sourceCallTransferred = YES;

        if (!self.isCallActive) {
            [self closeSheet:self];
        }
    }
}

@end
