//
//  AKKeychain.swift
//  Telephone
//
//  Swift implementation of the Objective-C AKKeychain interface.
//

import Foundation
import Security

@objc @implementation
extension AKKeychain {
    static func password(
        forService service: String,
        account: String
    ) -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard
            status == errSecSuccess,
            let data = result as? Data
        else {
            return ""
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    static func addItem(
        withService service: String,
        account: String,
        password: String
    ) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: Data(password.utf8),
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            return false
        }

        var newItem = query
        newItem[kSecValueData] = Data(password.utf8)
        return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
    }

    static func removeItem(
        forService service: String,
        account: String
    ) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
