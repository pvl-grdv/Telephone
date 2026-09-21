//
//  AKNetworkReachability.h
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

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const AKNetworkReachabilityDidBecomeReachableNotification;
extern NSString * const AKNetworkReachabilityDidBecomeUnreachableNotification;

/// Network.framework-backed path availability.
///
/// The host value is retained for diagnostics/API compatibility. Actual SIP
/// endpoint reachability is determined by PJSIP; this object only gates work
/// on whether macOS currently has a usable network path.
@interface AKNetworkReachability : NSObject

@property(nonatomic, readonly, copy) NSString *host;
@property(nonatomic, readonly, getter=isReachable) BOOL reachable;

+ (nullable AKNetworkReachability *)networkReachabilityWithHost:(NSString *)nameOrAddress;
- (nullable instancetype)initWithHost:(NSString *)nameOrAddress;

@end

NS_ASSUME_NONNULL_END
