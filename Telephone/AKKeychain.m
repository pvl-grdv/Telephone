//
//  AKKeychain.m
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

#import "AKKeychain.h"

@import Security;

@implementation AKKeychain

+ (nonnull NSString *)passwordForService:(nonnull NSString *)service account:(nonnull NSString *)account {
    NSParameterAssert(service);
    NSParameterAssert(account);

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
        (__bridge id)kSecReturnData: @YES
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || result == NULL) {
        if (result != NULL) {
            CFRelease(result);
        }
        return @"";
    }

    NSData *passwordData = CFBridgingRelease(result);
    NSString *password = [[NSString alloc] initWithData:passwordData encoding:NSUTF8StringEncoding];
    return password ?: @"";
}

+ (BOOL)addItemWithService:(nonnull NSString *)service
                   account:(nonnull NSString *)account
                  password:(nonnull NSString *)password {
    NSParameterAssert(service);
    NSParameterAssert(account);
    NSParameterAssert(password);

    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
        (__bridge id)kSecAttrAccount: account
    };

    NSDictionary *attributes = @{
        (__bridge id)kSecValueData: passwordData
    };

    OSStatus updateStatus = SecItemUpdate(
        (__bridge CFDictionaryRef)query,
        (__bridge CFDictionaryRef)attributes
    );
    if (updateStatus == errSecSuccess) {
        return YES;
    }
    if (updateStatus != errSecItemNotFound) {
        return NO;
    }

    NSMutableDictionary *newItem = [query mutableCopy];
    [newItem addEntriesFromDictionary:attributes];
    return SecItemAdd((__bridge CFDictionaryRef)newItem, NULL) == errSecSuccess;
}

@end
