//
//  AKSIPCallNotifications.h
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

@import Foundation;

// Calling. After INVITE is sent.
static NSString * const AKSIPCallCallingNotification = @"AKSIPCallCalling";
//
// Incoming. After INVITE is received.
static NSString * const AKSIPCallIncomingNotification = @"AKSIPCallIncoming";
//
// Early. After response with To tag.
// Keys: @"AKSIPEventCode", @"AKSIPEventReason".
static NSString * const AKSIPCallEarlyNotification = @"AKSIPCallEarly";
//
// Connecting. After 2xx is sent/received.
static NSString * const AKSIPCallConnectingNotification = @"AKSIPCallConnecting";
//
// Confirmed. After ACK is sent/received.
static NSString * const AKSIPCallDidConfirmNotification = @"AKSIPCallDidConfirm";
//
// Disconnected. Session is terminated.
static NSString * const AKSIPCallDidDisconnectNotification = @"AKSIPCallDidDisconnect";
//
// Call media is active.
static NSString * const AKSIPCallMediaDidBecomeActiveNotification = @"AKSIPCallMediaDidBecomeActive";
//
// Call media is put on hold by local endpoint.
static NSString * const AKSIPCallDidLocalHoldNotification = @"AKSIPCallDidLocalHold";
//
// Call media is put on hold by remote endpoint.
static NSString * const AKSIPCallDidRemoteHoldNotification = @"AKSIPCallDidRemoteHold";
//
// Call transfer status changed.
// Key: @"AKFinalTransferNotification".
static NSString * const AKSIPCallTransferStatusDidChangeNotification = @"AKSIPCallTransferStatusDidChange";
