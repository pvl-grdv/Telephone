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

@end


@implementation CallTransferController

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

    _sourceCallController = callController;
    [self showInitialState:self];
    return self;
}

- (void)transferCall {
    [self.sourceCallController.call attendedTransferToCall:self.call];
}

- (void)closeSheet:(id)sender {
    CallController *sourceCallController = self.sourceCallController;
    if (sourceCallController.isCallActive &&
        sourceCallController.isCallOnHold) {
        [sourceCallController toggleCallHold];
    }

    [sourceCallController dismissCallTransfer];
    [sourceCallController discardCallTransfer];
}

- (void)showInitialState:(id)sender {
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

- (void)SIPCallDidDisconnect:(NSNotification *)notification {
    [super SIPCallDidDisconnect:notification];
}

- (void)SIPCallDidLocalHold:(NSNotification *)notification {
    [super SIPCallDidLocalHold:notification];
    [self callDidHoldForTransfer];
}


@end
