//
//  ActiveAccountViewController.h
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

#import <Cocoa/Cocoa.h>


extern NSNotificationName const AKContactsAuthorizationDidChangeNotification;

@class AccountController, AKSIPURI;

// An active account view controller.
@interface ActiveAccountViewController : NSViewController {
    AccountController * __weak _accountController;
}

@property(nonatomic, readonly, weak) AccountController *accountController;

// Call destination token field outlet.
@property(nonatomic, weak) IBOutlet NSTokenField *callDestinationField;

// Selected call destination.
@property(nonatomic, readonly, copy) AKSIPURI *callDestinationURI;
@property(nonatomic, readonly, copy) NSString *callDestinationPhoneLabel;

@property(nonatomic, readonly) BOOL allowsCallDestinationInput;
@property(nonatomic, readonly) NSView *keyView;

- (instancetype)initWithAccountController:(AccountController *)accountController NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(NSNibName)name bundle:(NSBundle *)bundle NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

// Makes a call.
- (IBAction)makeCall:(id)sender;

- (void)allowCallDestinationInput;
- (void)disallowCallDestinationInput;

- (void)updateNextKeyView:(NSView *)view;

@end
