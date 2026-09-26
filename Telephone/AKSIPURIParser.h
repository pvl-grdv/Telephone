//
//  AKSIPURIParser.h
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

@class AKSIPURI, AKSIPUserAgent;

@interface AKSIPURIParser : NSObject

@property(nonatomic, readonly, weak, nullable) AKSIPUserAgent *agent;

- (instancetype)initWithUserAgent:(AKSIPUserAgent *)agent NS_SWIFT_NAME(init(userAgent:));

- (nullable AKSIPURI *)SIPURIFromString:(NSString *)string NS_SWIFT_NAME(sipURI(from:));

@end

NS_ASSUME_NONNULL_END
