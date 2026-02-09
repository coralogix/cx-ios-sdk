//
//  CloudKitTestHelper.swift
//  DemoAppSwift
//
//  Helper to force-link CloudKit for testing UserDefaults corruption
//

import Foundation
import CloudKit

/// This class forces CloudKit to be linked and available for testing
/// Without this, CloudKit classes won't be loaded even if framework is linked
final class CloudKitTestHelper {
    
    /// Call this early in app lifecycle to ensure CloudKit is loaded
    static func forceLoadCloudKit() {
        // These references force CloudKit classes to be loaded into memory
        // without actually using them
        _ = CKDatabase.self
        _ = CKContainer.self
        _ = CKRecord.self
        _ = CKRecordZone.self
        
        print("☁️ CloudKit classes loaded for testing")
    }
    
    /// Check if CloudKit is available
    static func isCloudKitAvailable() -> Bool {
        return NSClassFromString("CKDatabase") != nil
    }
}
