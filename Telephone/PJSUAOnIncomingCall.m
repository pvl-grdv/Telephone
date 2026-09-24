//
//  PJSUAOnIncomingCall.m
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

#import "PJSUACallbacks.h"

#import "AKSIPAccount.h"
#import "AKSIPCall.h"
#import "AKSIPURIParser.h"
#import "AKSIPUserAgent.h"
#import "PJSUACallInfo.h"

#define THIS_FILE "PJSUAOnIncomingCall.m"

static NSString *HeaderValue(pjsip_rx_data *invite, const char *name) {
    if (invite == NULL || invite->msg_info.msg == NULL) {
        return nil;
    }

    pj_str_t headerName = pj_str((char *)name);
    pjsip_hdr *header = pjsip_msg_find_hdr_by_name(
        invite->msg_info.msg,
        &headerName,
        NULL
    );
    if (header == NULL) {
        return nil;
    }

    char buffer[2048];
    int length = pjsip_hdr_print_on(
        header,
        buffer,
        sizeof(buffer) - 1
    );
    if (length <= 0 || length >= (int)sizeof(buffer)) {
        return nil;
    }
    buffer[length] = '\0';

    NSString *line = [NSString stringWithUTF8String:buffer];
    if (line.length == 0) {
        return nil;
    }

    NSRange separator = [line rangeOfString:@":"];
    NSString *value = separator.location == NSNotFound
        ? line
        : [line substringFromIndex:NSMaxRange(separator)];
    return [value stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSDictionary<NSString *, NSString *> *IdentityHeaders(
    pjsip_rx_data *invite
) {
    static NSArray<NSString *> *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @[
            @"P-Asserted-Identity",
            @"P-Preferred-Identity",
            @"Remote-Party-ID",
            @"Diversion",
            @"History-Info",
            @"X-Caller-ID",
            @"X-Caller-Name",
            @"X-Customer-ID",
            @"X-Company"
        ];
    });

    NSMutableDictionary<NSString *, NSString *> *result =
        [NSMutableDictionary dictionary];
    for (NSString *name in names) {
        NSString *value = HeaderValue(invite, name.UTF8String);
        if (value.length > 0) {
            result[name] = value;
        }
    }
    return result;
}

void PJSUAOnIncomingCall(pjsua_acc_id accountID, pjsua_call_id callID, pjsip_rx_data *invite) {
    PJ_LOG(3, (THIS_FILE, "Incoming call for account %d", accountID));
    pjsua_call_info info;
    pjsua_call_get_info(callID, &info);
    AKSIPUserAgent *agent = [AKSIPUserAgent sharedUserAgent];
    PJSUACallInfo *infoWrapper = [[PJSUACallInfo alloc] initWithInfo:info parser:agent.parser];
    NSDictionary<NSString *, NSString *> *identityHeaders =
        IdentityHeaders(invite);
    if (identityHeaders.count > 0) {
        PJ_LOG(
            4,
            (
                THIS_FILE,
                "Incoming identity headers: %s",
                identityHeaders.description.UTF8String
            )
        );
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        AKSIPAccount *account = [agent accountWithIdentifier:accountID];
        AKSIPCall *call = [account addCallWithInfo:infoWrapper];
        call.incomingIdentityHeaders = identityHeaders;
        [account.delegate SIPAccount:account didReceiveCall:call];
        [[NSNotificationCenter defaultCenter] postNotificationName:AKSIPCallIncomingNotification object:call];
    });
}
