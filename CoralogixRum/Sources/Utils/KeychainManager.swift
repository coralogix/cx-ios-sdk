//
//  KeychainManager.swift
//  
//
//  Created by Coralogix DEV TEAM on 09/05/2024.
//

import Foundation

class KeychainManager: KeyChainProtocol {
    // Function to read a string from Keychain
    func readStringFromKeychain(service: String, key: String) -> String? {
        // Create the Keychain query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        
        // Retrieve the item from the Keychain
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let stringValue = String(data: data, encoding: .utf8) else {
            Log.e("Failed to read data from Keychain")
            return nil
        }
        
        return stringValue
    }
    
    // Function to save a string into Keychain
    func writeStringToKeychain(service: String, key: String, value: String) {
        // Convert the string value to Data
        guard let data = value.data(using: .utf8) else {
            Log.e("Failed to convert string to data")
            return
        }
        
        // Create the Keychain query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Delete existing item before adding new one
        SecItemDelete(query as CFDictionary)
        
        // Add the item to the Keychain
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Log.e("Failed to save data to Keychain")
        }
    }
}
