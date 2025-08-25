//
//  FingerprintManager.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 24/08/2025.
//

import Foundation

public class FingerprintManager {
    public let fingerprint: String
    private static let createLock = NSLock()

    init(using keychain: KeyChainProtocol) {
        self.fingerprint = FingerprintManager.resolveFingerprint(using: keychain)
    }
    
    private static func resolveFingerprint(using keychain: KeyChainProtocol) -> String {
        // 1) Try existing
        if let existing = keychain.readStringFromKeychain(service: Keys.service.rawValue,
                                                          key: Keys.fingerPrint.rawValue) {
            return existing
        }
        
        // Serialize creation
        createLock.lock()
        defer { createLock.unlock() }
        
        // Re-check after acquiring the lock (double-checked)
        if let existing = keychain.readStringFromKeychain(service: Keys.service.rawValue,
                                                          key: Keys.fingerPrint.rawValue) {
            return existing
        }
        
        // 2) Generate candidate
        let candidate = UUID().uuidString.lowercased()
        
        // 3) Try to persist
        keychain.writeStringToKeychain(service: Keys.service.rawValue,
                                       key: Keys.fingerPrint.rawValue,
                                       value: candidate)
        
        // 4) Read back to converge if another thread raced and wrote a different value
        //    (This handles "lost update" and ensures all instances agree on the persisted value.)
        return keychain.readStringFromKeychain(service: Keys.service.rawValue,
                                               key: Keys.fingerPrint.rawValue) ?? candidate
    }
    
    // Test-only convenience (doesn't touch keychain)
#if DEBUG
    init(testFingerprint: String) {
        self.fingerprint = testFingerprint
    }
#endif
}

