//
//  AppController.h
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

@import Cocoa;

#import "AKSIPUserAgent.h"

NS_ASSUME_NONNULL_BEGIN

@interface AppController : NSObject <NSApplicationDelegate, AKSIPUserAgentDelegate>

- (void)updateDockTileBadgeLabel;
- (void)copySettings;
- (void)showLogFile;
- (void)openHomepage;
- (void)openFAQ;

- (id)accountsCommandModelForSwiftUI;
- (void)showPreferencesForSwiftUI;

- (BOOL)makeCallFromAppIntentWithDestination:(NSString *)destination
    NS_SWIFT_NAME(makeCallFromAppIntent(destination:));
- (BOOL)setAccountAvailabilityFromAppIntentWithUUID:(NSString * _Nonnull)uuid
                                              state:(NSInteger)state
    NS_SWIFT_NAME(setAccountAvailabilityFromAppIntent(uuid:state:));

@end

NS_ASSUME_NONNULL_END
