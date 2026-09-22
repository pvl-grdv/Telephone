//
//  ActiveAccountViewController.m
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

#import "ActiveAccountViewController.h"

@import Contacts;
@import UseCases;

#import "AKSIPURI.h"
#import "AKSIPURIFormatter.h"
#import "AKTelephoneNumberFormatter.h"

#import "AccountController.h"

#import "Telephone-Swift.h"


NSString * const kURI = @"URI";
NSString * const kPhoneLabel = @"PhoneLabel";
NSNotificationName const AKContactsAuthorizationDidChangeNotification =
    @"TelephoneContactsAuthorizationDidChange";

@interface ActiveAccountViewController ()

@property(nonatomic) CNContactStore *contactStore;
@property(nonatomic, copy) NSArray<CNContact *> *contactsCache;
@property(nonatomic) BOOL contactsCacheLoading;
@property(nonatomic) BOOL contactsPermissionRequestInFlight;

@end

static BOOL HasCaseInsensitivePrefix(NSString *value, NSString *prefix) {
    if (value.length == 0 || prefix.length == 0) {
        return NO;
    }
    return [value rangeOfString:prefix options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location != NSNotFound;
}

static NSString *ContactDisplayName(CNContact *contact) {
    NSString *name = [CNContactFormatter stringFromContact:contact style:CNContactFormatterStyleFullName];
    if (name.length == 0) {
        name = contact.organizationName;
    }
    return name ?: @"";
}

static NSString *LocalizedContactLabel(NSString *label) {
    if (label.length == 0) {
        return @"";
    }
    return [CNLabeledValue localizedStringForLabel:label] ?: label;
}

static BOOL IsSIPLabel(NSString *label) {
    if (label.length == 0) {
        return NO;
    }
    NSString *localized = LocalizedContactLabel(label);
    return [label caseInsensitiveCompare:@"sip"] == NSOrderedSame ||
           [localized caseInsensitiveCompare:@"sip"] == NSOrderedSame;
}

static NSArray<CNContact *> *AllContacts(CNContactStore *store) {
    NSMutableArray<CNContact *> *contacts = [NSMutableArray array];
    NSArray *keys = @[
        [CNContactFormatter descriptorForRequiredKeysForStyle:CNContactFormatterStyleFullName],
        CNContactGivenNameKey,
        CNContactFamilyNameKey,
        CNContactOrganizationNameKey,
        CNContactPhoneNumbersKey,
        CNContactEmailAddressesKey
    ];
    CNContactFetchRequest *request = [[CNContactFetchRequest alloc] initWithKeysToFetch:keys];
    NSError *error = nil;
    BOOL success = [store enumerateContactsWithFetchRequest:request
                                                     error:&error
                                                usingBlock:^(CNContact *contact, BOOL *stop) {
        [contacts addObject:contact];
    }];
    if (!success) {
        NSLog(@"Could not enumerate contacts for autocomplete: %@", error);
    }
    return contacts;
}

static BOOL ContactMatchesName(CNContact *contact, NSString *query) {
    NSString *givenFamily = [NSString stringWithFormat:@"%@ %@", contact.givenName, contact.familyName];
    NSString *familyGiven = [NSString stringWithFormat:@"%@ %@", contact.familyName, contact.givenName];
    return HasCaseInsensitivePrefix(ContactDisplayName(contact), query) ||
           HasCaseInsensitivePrefix(contact.givenName, query) ||
           HasCaseInsensitivePrefix(contact.familyName, query) ||
           HasCaseInsensitivePrefix(givenFamily, query) ||
           HasCaseInsensitivePrefix(familyGiven, query) ||
           HasCaseInsensitivePrefix(contact.organizationName, query);
}

static NSString *NormalizedPhoneNumber(NSString *value) {
    AKTelephoneNumberFormatter *formatter = [[AKTelephoneNumberFormatter alloc] init];
    return [formatter telephoneNumberFromString:value] ?: @"";
}

static BOOL PhoneMatchesPrefix(NSString *phoneNumber, NSString *query) {
    NSString *normalizedPhone = NormalizedPhoneNumber(phoneNumber);
    NSString *normalizedQuery = NormalizedPhoneNumber(query);
    return normalizedQuery.length > 0 && [normalizedPhone hasPrefix:normalizedQuery];
}

static BOOL ContactNameEquals(CNContact *contact, NSString *name) {
    if (name.length == 0) {
        return YES;
    }
    return [ContactDisplayName(contact) caseInsensitiveCompare:name] == NSOrderedSame ||
           [contact.organizationName caseInsensitiveCompare:name] == NSOrderedSame;
}

static CNContact *ContactMatchingURI(NSArray<CNContact *> *contacts, AKSIPURI *uri, NSString *displayedName) {
    CNContact *fallback = nil;

    for (CNContact *contact in contacts) {
        BOOL addressMatches = NO;
        if (uri.host.length == 0) {
            NSString *target = NormalizedPhoneNumber(uri.user);
            for (CNLabeledValue<CNPhoneNumber *> *phone in contact.phoneNumbers) {
                if (target.length > 0 && [NormalizedPhoneNumber(phone.value.stringValue) isEqualToString:target]) {
                    addressMatches = YES;
                    break;
                }
            }
        } else {
            NSString *target = uri.SIPAddress;
            for (CNLabeledValue<NSString *> *email in contact.emailAddresses) {
                if (IsSIPLabel(email.label) &&
                    [(NSString *)email.value caseInsensitiveCompare:target] == NSOrderedSame) {
                    addressMatches = YES;
                    break;
                }
            }
        }

        if (!addressMatches) {
            continue;
        }
        if (ContactNameEquals(contact, displayedName)) {
            return contact;
        }
        if (fallback == nil) {
            fallback = contact;
        }
    }
    return fallback;
}

@implementation ActiveAccountViewController

- (AKSIPURI *)callDestinationURI {
    NSDictionary *callDestinationDict = [[self callDestinationField] objectValue][0][[self callDestinationURIIndex]];
    
    AKSIPURI *uri = [callDestinationDict[kURI] copy];
    
    // Displayed name is stored in the first URI only.
    AKSIPURI *firstURI = [[self callDestinationField] objectValue][0][0][kURI];
    
    [uri setDisplayName:[firstURI displayName]];
    
    if ([uri isKindOfClass:[AKSIPURI class]] && [[uri user] length] > 0) {
        return uri;
    } else {
        return nil;
    }
}

- (BOOL)allowsCallDestinationInput {
    return !self.callDestinationField.isHidden;
}

- (NSView *)keyView {
    return self.callDestinationField;
}

- (instancetype)initWithAccountController:(AccountController *)accountController {
    NSParameterAssert(accountController);
    if ((self = [super initWithNibName:@"ActiveAccountView" bundle:nil])) {
        _accountController = accountController;
    }
    return self;
}

- (instancetype)initWithNibName:(NSNibName)name bundle:(NSBundle *)bundle {
    return self = [super initWithNibName:name bundle:bundle];
}

- (void)awakeFromNib {
    // Exclude comma from the callDestination tokenizing character set.
    [[self callDestinationField] setTokenizingCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@""]];
    
    [[self callDestinationField] setCompletionDelay:0.4];

    self.contactStore = [[CNContactStore alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contactsDidChange:)
                                                 name:CNContactStoreDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(callDestinationTextDidBeginEditing:)
                                                 name:NSControlTextDidBeginEditingNotification
                                               object:self.callDestinationField];

    CNAuthorizationStatus status = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
    if (status == CNAuthorizationStatusAuthorized) {
        [self refreshContactsCache];
    }
}

- (void)callDestinationTextDidBeginEditing:(NSNotification *)notification {
    [self requestContactsAccessIfNeeded];
}

- (void)requestContactsAccessIfNeeded {
    CNAuthorizationStatus status = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];

    if (status == CNAuthorizationStatusAuthorized) {
        if (self.contactsCache == nil) {
            [self refreshContactsCache];
        }
        return;
    }

    if (status != CNAuthorizationStatusNotDetermined || self.contactsPermissionRequestInFlight) {
        return;
    }

    self.contactsPermissionRequestInFlight = YES;
    __weak typeof(self) weakSelf = self;
    [self.contactStore requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }

            strongSelf.contactsPermissionRequestInFlight = NO;
            if (!granted) {
                if (error != nil) {
                    NSLog(@"Could not get Contacts access: %@", error);
                }
                return;
            }

            [strongSelf refreshContactsCache];
            [[NSNotificationCenter defaultCenter]
                postNotificationName:AKContactsAuthorizationDidChangeNotification
                              object:nil];
        });
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)contactsDidChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        CNAuthorizationStatus status = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
        if (status == CNAuthorizationStatusAuthorized) {
            [self refreshContactsCache];
        } else {
            self.contactsCache = @[];
        }
    });
}

- (void)refreshContactsCache {
    if (self.contactsCacheLoading) {
        return;
    }

    self.contactsCacheLoading = YES;
    CNContactStore *store = self.contactStore;
    __weak typeof(self) weakSelf = self;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<CNContact *> *contacts = AllContacts(store);
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            strongSelf.contactsCache = contacts;
            strongSelf.contactsCacheLoading = NO;
        });
    });
}

- (IBAction)makeCall:(id)sender {
    if (![self canMakeCall]) {
        return;
    }
    
    NSDictionary *callDestinationDict = [[self callDestinationField] objectValue][0][[self callDestinationURIIndex]];
    NSString *phoneLabel = callDestinationDict[kPhoneLabel];
    
    AKSIPURI *uri = [self callDestinationURI];
    if (uri != nil) {
        [[self accountController] makeCallToURI:uri phoneLabel:phoneLabel];
    }
}

- (BOOL)canMakeCall {
    return [self.callDestinationField.objectValue count] > 0 &&
    [self.callDestinationField.objectValue isKindOfClass:[NSArray class]] &&
    [self.callDestinationField.objectValue[0] isKindOfClass:[NSArray class]] &&
    [self.callDestinationField.objectValue[0][self.callDestinationURIIndex] isKindOfClass:[NSDictionary class]];
}

- (IBAction)changeCallDestinationURIIndex:(id)sender {
    [self setCallDestinationURIIndex:[sender tag]];
}

- (void)allowCallDestinationInput {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        self.callDestinationField.animator.hidden = NO;
    } completionHandler:^{
        if (self.callDestinationField.acceptsFirstResponder) {
            [self.view.window makeFirstResponder:self.callDestinationField];
        }
    }];
}

- (void)disallowCallDestinationInput {
    self.callDestinationField.hidden = YES;
}

- (void)updateNextKeyView:(NSView *)view {
    self.keyView.nextKeyView = view;
}


#pragma mark -
#pragma mark NSTokenField delegate

// Returns completions based on the Contacts search.
// A completion string can be in one of two formats: Display Name <1234567> for person or company name searches,
// 1234567 (Display Name) for the phone number searches.
// Sets tokenField sytle to NSTokenStyleRounded if the substring is found in Contacts; otherwise, sets
// tokenField sytle to NSPlainTextTokenStyle.
- (NSArray *)tokenField:(NSTokenField *)tokenField
        completionsForSubstring:(NSString *)substring
        indexOfToken:(NSInteger)tokenIndex
        indexOfSelectedItem:(NSInteger *)selectedIndex {

    NSString *query = [substring stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) {
        [tokenField setTokenStyle:NSTokenStyleNone];
        return @[];
    }

    NSArray<CNContact *> *contacts = self.contactsCache ?: @[];

    NSMutableOrderedSet<NSString *> *completionSet = [NSMutableOrderedSet orderedSet];
    for (CNContact *contact in contacts) {
        NSString *name = ContactDisplayName(contact);
        BOOL nameMatches = ContactMatchesName(contact, query);

        for (CNLabeledValue<CNPhoneNumber *> *phone in contact.phoneNumbers) {
            NSString *number = phone.value.stringValue;
            if (PhoneMatchesPrefix(number, query)) {
                [completionSet addObject:name.length > 0
                    ? [NSString stringWithFormat:@"%@ (%@)", number, name]
                    : number];
            }
            if (nameMatches) {
                [completionSet addObject:name.length > 0
                    ? [NSString stringWithFormat:@"%@ <%@>", name, number]
                    : number];
            }
        }

        for (CNLabeledValue<NSString *> *email in contact.emailAddresses) {
            if (!IsSIPLabel(email.label)) {
                continue;
            }
            NSString *address = (NSString *)email.value;
            if (HasCaseInsensitivePrefix(address, query)) {
                [completionSet addObject:name.length > 0
                    ? [NSString stringWithFormat:@"%@ (%@)", address, name]
                    : address];
            }
            if (nameMatches) {
                [completionSet addObject:name.length > 0
                    ? [NSString stringWithFormat:@"%@ <%@>", name, address]
                    : address];
            }
        }
    }

    NSMutableArray<NSString *> *completions = [completionSet.array mutableCopy];

    // Preserve capitalization of the typed prefix for the first completion.
    if (completions.count > 0) {
        NSRange searchedStringRange = [completions[0] rangeOfString:query options:NSCaseInsensitiveSearch];
        if (searchedStringRange.location == 0) {
            completions[0] = [completions[0] stringByReplacingCharactersInRange:NSMakeRange(0, query.length)
                                                                      withString:query];
        }
    }

    [tokenField setTokenStyle:completions.count > 0 ? NSTokenStyleRounded : NSTokenStyleNone];
    return [completions copy];
}

// Converts input text to the array of dictionaries containing AKSIPURIs and phone labels (mobile, home, etc).
// Dictionary keys are kURI and kPhoneLabel. If there is no @ sign, the input is treated as a user part of the URI and
// host part will be nil.
- (id)tokenField:(NSTokenField *)tokenField representedObjectForEditingString:(NSString *)editingString {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    AKSIPURIFormatter *SIPURIFormatter = [[AKSIPURIFormatter alloc] init];
    [SIPURIFormatter setFormatsTelephoneNumbers:[defaults boolForKey:UserDefaultsKeys.formatTelephoneNumbers]];
    [SIPURIFormatter setTelephoneNumberFormatterSplitsLastFourDigits:
     [defaults boolForKey:UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits]];

    NSString *trimmedString = [editingString stringByTrimmingCharactersInSet:
                               [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    AKSIPURI *theURI = [SIPURIFormatter SIPURIFromString:trimmedString];
    if (theURI == nil || theURI.user.length == 0) {
        return nil;
    }

    NSArray<CNContact *> *contacts = self.contactsCache ?: @[];
    CNContact *contact = ContactMatchingURI(contacts, theURI, theURI.displayName);

    NSMutableArray *callDestinations = [[NSMutableArray alloc] init];
    NSUInteger destinationIndex = 0;

    if (contact != nil) {
        NSString *displayName = ContactDisplayName(contact);
        if (displayName.length > 0) {
            [theURI setDisplayName:displayName];
        }

        NSString *targetPhone = NormalizedPhoneNumber(theURI.user);
        for (CNLabeledValue<CNPhoneNumber *> *phone in contact.phoneNumbers) {
            NSString *phoneNumber = phone.value.stringValue;
            AKSIPURI *uri = [SIPURIFormatter SIPURIFromString:phoneNumber];
            if (uri == nil) {
                continue;
            }
            [uri setDisplayName:theURI.displayName];
            [callDestinations addObject:@{
                kURI: uri,
                kPhoneLabel: LocalizedContactLabel(phone.label)
            }];

            if (theURI.host.length == 0 &&
                targetPhone.length > 0 &&
                [NormalizedPhoneNumber(phoneNumber) isEqualToString:targetPhone]) {
                destinationIndex = callDestinations.count - 1;
            }
        }

        for (CNLabeledValue<NSString *> *email in contact.emailAddresses) {
            if (!IsSIPLabel(email.label)) {
                continue;
            }

            NSString *address = (NSString *)email.value;
            AKSIPURI *uri = [SIPURIFormatter SIPURIFromString:address];
            if (uri == nil) {
                continue;
            }
            [uri setDisplayName:theURI.displayName];
            [callDestinations addObject:@{
                kURI: uri,
                kPhoneLabel: LocalizedContactLabel(email.label)
            }];

            if ([address caseInsensitiveCompare:theURI.SIPAddress] == NSOrderedSame) {
                destinationIndex = callDestinations.count - 1;
            }
        }
    }

    if (callDestinations.count == 0) {
        [callDestinations addObject:@{kURI: theURI, kPhoneLabel: @""}];
    }

    [self setCallDestinationURIIndex:destinationIndex];
    return [callDestinations copy];
}

- (NSString *)tokenField:(NSTokenField *)tokenField displayStringForRepresentedObject:(id)representedObject {
    if (![representedObject isKindOfClass:[NSArray class]]) {
        return nil;
    }
    
    AKSIPURI *uri = representedObject[[self callDestinationURIIndex]][kURI];
    
    NSString *returnString = nil;
    
    if ([[uri displayName] length] > 0) {
        returnString = [uri displayName];
        
    } else if ([[uri host] length] > 0) {
        NSAssert(([[uri user] length] > 0), @"User part of the URI must not have zero length in this context");
        
        returnString = [uri SIPAddress];
        
    } else {
        NSAssert(([[uri user] length] > 0), @"User part of the URI must not have zero length in this context");
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([[uri user] ak_isTelephoneNumber] && [defaults boolForKey:UserDefaultsKeys.formatTelephoneNumbers]) {
            AKTelephoneNumberFormatter *formatter = [[AKTelephoneNumberFormatter alloc] init];
            [formatter setSplitsLastFourDigits:[defaults boolForKey:UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits]];
            returnString = [formatter stringForObjectValue:[uri user]];
            
        } else {
            returnString = [uri user];
        }
    }
    
    return returnString;
}

- (NSString *)tokenField:(NSTokenField *)tokenField editingStringForRepresentedObject:(id)representedObject {
    if (![representedObject isKindOfClass:[NSArray class]]) {
        return nil;
    }
    
    AKSIPURI *uri = representedObject[[self callDestinationURIIndex]][kURI];
    
    NSAssert(([[uri user] length] > 0), @"User part of the URI must not have zero length in this context");
    
    NSString *returnString = nil;
    
    if ([[uri displayName] length] > 0) {
        if ([[uri host] length] > 0) {
            returnString = [NSString stringWithFormat:@"%@ <%@>", [uri displayName], [uri SIPAddress]];
        } else {
            returnString =  [NSString stringWithFormat:@"%@ <%@>", [uri displayName], [uri user]];
        }
    } else if ([[uri host] length] > 0) {
        returnString =  [uri SIPAddress];
        
    } else {
        returnString =  [uri user];
    }
    
    return returnString;
}

- (BOOL)tokenField:(NSTokenField *)tokenField hasMenuForRepresentedObject:(id)representedObject {
    AKSIPURI *uri = representedObject[[self callDestinationURIIndex]][kURI];
    
    if ([representedObject isKindOfClass:[NSArray class]] && [[uri displayName] length] > 0) {
        return YES;
    } else {
        return NO;
    }
}

- (NSMenu *)tokenField:(NSTokenField *)tokenField menuForRepresentedObject:(id)representedObject {
    NSMenu *tokenMenu = [[NSMenu alloc] init];
    
    for (NSUInteger i = 0; i < [representedObject count]; ++i) {
        AKSIPURI *uri = representedObject[i][kURI];
        
        NSString *phoneLabel = representedObject[i][kPhoneLabel];
        
        NSMenuItem *menuItem = [[NSMenuItem alloc] init];
        
        AKTelephoneNumberFormatter *formatter = [[AKTelephoneNumberFormatter alloc] init];
        [formatter setSplitsLastFourDigits:
         [[NSUserDefaults standardUserDefaults] boolForKey:UserDefaultsKeys.telephoneNumberFormatterSplitsLastFourDigits]];
        
        if ([[uri host] length] > 0) {
            [menuItem setTitle:[NSString stringWithFormat:@"%@: %@", phoneLabel, [uri SIPAddress]]];
            
        } else if ([[uri user] ak_isTelephoneNumber]) {
            [menuItem setTitle:[NSString stringWithFormat:@"%@: %@",
                                phoneLabel, [formatter stringForObjectValue:[uri user]]]];
        } else {
            [menuItem setTitle:[NSString stringWithFormat:@"%@: %@", phoneLabel, [uri user]]];
        }
        
        [menuItem setTag:i];
        [menuItem setAction:@selector(changeCallDestinationURIIndex:)];
        
        [tokenMenu addItem:menuItem];
    }
    
    [[tokenMenu itemWithTag:[self callDestinationURIIndex]] setState:NSControlStateValueOn];
    
    return tokenMenu;
}

- (NSArray *)tokenField:(NSTokenField *)tokenField shouldAddObjects:(NSArray *)tokens atIndex:(NSUInteger)index {
    if (index > 0 && [tokenField tokenStyle] == NSTokenStyleRounded) {
        return nil;
    } else {
        return tokens;
    }
}

@end
