//
//  AKSIPURI.h
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

NS_ASSUME_NONNULL_BEGIN

@interface AKSIPURI : NSObject <NSCopying>

@property(nonatomic, readonly, copy) NSString *SIPAddress NS_SWIFT_NAME(sipAddress);

@property(nonatomic, copy) NSString *user;
@property(nonatomic, copy) NSString *host;
@property(nonatomic, copy) NSString *displayName;

@property(nonatomic, assign) NSInteger port;

+ (instancetype)SIPURIWithUser:(NSString *)user host:(NSString *)host displayName:(NSString *)displayName NS_SWIFT_NAME(sipURI(user:host:displayName:));
+ (nullable instancetype)SIPURIWithString:(NSString *)SIPURIString NS_SWIFT_NAME(sipURI(string:));

- (instancetype)initWithUser:(NSString *)user host:(NSString *)host displayName:(NSString *)displayName port:(NSInteger)port NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(user:host:displayName:port:));
- (instancetype)initWithUser:(NSString *)user host:(NSString *)host displayName:(NSString *)displayName NS_SWIFT_NAME(init(user:host:displayName:));

- (nullable instancetype)initWithString:(NSString *)SIPURIString NS_SWIFT_NAME(init(string:));

@end

NS_ASSUME_NONNULL_END
