//
//  Log.swift
//
//  Created by Coralogix DEV TEAM on 02/04/2024.
//

import Foundation

public class Log {
    public static var isDebug = false

    public static func d(_ message: String) {
        debug(message)
    }
    
    public static func debug(_ message: String) {
        if isDebug {
            print("🟪 \(message)")
        }
    }
    
    // MARK: - Trace
    
    public static func t(_ message: String) {
        trace(message)
    }
    
    public static func trace(_ message: String) {
        if isDebug {
            print("🟦 \(message)")
        }
    }
    
    // MARK: - Warning

    public static func w(_ message: String) {
        warning(message)
    }
    
    public static func warning(_ message: String) {
        if isDebug {
            print("🟨 \(message)")
        }
    }
    
    // MARK: - Error

    public static func e(_ message: String = "", _ error: Error? = nil) {
        Log.error(message, error)
    }
    
    public static func error(_ message: String = "", _ error: Error? = nil) {
        if isDebug {
            var description = message
            if let error = error {
                description = "\(description)\ndetails:\n\(error.localizedDescription)"
            }
            print("🟥 \(description)")
        }
    }
    
    public static func e(_ error: Error) {
        Log.error(error)
    }
    
    public static func error(_ error: Error) {
        print("🟥 \(error.localizedDescription)")
    }
    
    // MARK: - Test Logging (DEBUG only)
    
    #if DEBUG
    private static var isTestLoggingEnabled = false
    private static let testLogFileURL = URL(fileURLWithPath: "/tmp/coralogix_test_logs.txt")
    private static let testLogQueue = DispatchQueue(label: "com.coralogix.testlogger", qos: .utility)
    
    public static func enableTestLogging() {
        testLogQueue.sync {
            isTestLoggingEnabled = true
            // Clear previous logs
            try? "".write(to: testLogFileURL, atomically: true, encoding: .utf8)
        }
    }
    
    public static func disableTestLogging() {
        testLogQueue.sync {
            isTestLoggingEnabled = false
        }
    }
    
    public static func testLog(_ message: String) {
        testLogQueue.async {
            // Read flag under queue protection to avoid race with enable/disable
            guard isTestLoggingEnabled else { return }
            
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let logEntry = "[\(timestamp)] \(message)\n"
            
            if let handle = try? FileHandle(forWritingTo: testLogFileURL) {
                handle.seekToEndOfFile()
                if let data = logEntry.data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
            } else {
                try? logEntry.write(to: testLogFileURL, atomically: true, encoding: .utf8)
            }
        }
    }
    
    public static func getTestLogs() -> String {
        // Synchronize with testLogQueue to ensure all pending writes complete before reading
        return testLogQueue.sync {
            return (try? String(contentsOf: testLogFileURL, encoding: .utf8)) ?? ""
        }
    }
    
    public static func clearTestLogs() {
        testLogQueue.sync {
            try? "".write(to: testLogFileURL, atomically: true, encoding: .utf8)
        }
    }
    #endif
}
