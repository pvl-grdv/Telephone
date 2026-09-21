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

extern NSString * const AKNetworkReachabilityDidChangeNotification;

/// Network.framework-backed default path availability.
///
/// This object observes macOS network path changes. It does not probe or
/// determine reachability of a SIP registrar; PJSIP remains the source of
/// truth for SIP registration and call connectivity.
@interface AKNetworkReachability : NSObject

@property(nonatomic, readonly, getter=isReachable) BOOL reachable;

+ (instancetype)networkReachability;

@end

NS_ASSUME_NONNULL_END
