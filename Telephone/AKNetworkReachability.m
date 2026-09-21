//
//  AKNetworkReachability.m
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//  Modifications © 2026 Pavel Gordeev
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

#import "AKNetworkReachability.h"

@import Network;

NSString * const AKNetworkReachabilityDidBecomeReachableNotification = @"AKNetworkReachabilityDidBecomeReachable";
NSString * const AKNetworkReachabilityDidBecomeUnreachableNotification = @"AKNetworkReachabilityDidBecomeUnreachable";

@interface AKNetworkReachability ()

@property(nonatomic, copy) NSString *host;
@property(nonatomic, getter=isReachable) BOOL reachable;
@property(nonatomic, strong) nw_path_monitor_t monitor;
@property(nonatomic, strong) dispatch_queue_t monitorQueue;

@end

@implementation AKNetworkReachability

+ (nullable AKNetworkReachability *)networkReachabilityWithHost:(NSString *)nameOrAddress {
    return [[self alloc] initWithHost:nameOrAddress];
}

- (nullable instancetype)initWithHost:(NSString *)nameOrAddress {
    self = [super init];
    if (self == nil || nameOrAddress.length == 0) {
        return nil;
    }

    _host = [nameOrAddress copy];
    _reachable = NO;
    _monitor = nw_path_monitor_create();
    _monitorQueue = dispatch_queue_create("com.tlphn.Telephone.network-path", DISPATCH_QUEUE_SERIAL);

    __weak typeof(self) weakSelf = self;
    nw_path_monitor_set_update_handler(_monitor, ^(nw_path_t path) {
        BOOL reachable = nw_path_get_status(path) == nw_path_status_satisfied;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil || strongSelf.reachable == reachable) {
                return;
            }

            strongSelf.reachable = reachable;
            NSString *name = reachable
                ? AKNetworkReachabilityDidBecomeReachableNotification
                : AKNetworkReachabilityDidBecomeUnreachableNotification;
            [[NSNotificationCenter defaultCenter] postNotificationName:name object:strongSelf];
        });
    });
    nw_path_monitor_set_queue(_monitor, _monitorQueue);
    nw_path_monitor_start(_monitor);

    return self;
}

- (void)dealloc {
    if (_monitor != nil) {
        nw_path_monitor_cancel(_monitor);
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ network path", self.host];
}

@end
