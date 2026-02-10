//
//  TestLogger.swift
//  Coralogix
//
//  Created by Coralogix DEV TEAM on 05/02/2026.
//
//  Simple file logger for UI testing validation
//

import Foundation

#if DEBUG
public class TestLogger {
    public static let shared = TestLogger()
    
    private var isEnabled = false
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.coralogix.testlogger", qos: .utility)
    
    init() {
        // Use a fixed path in /tmp that's accessible from both app and UI tests
        fileURL = URL(fileURLWithPath: "/tmp/coralogix_test_logs.txt")
    }
    
    public func enable() {
        queue.sync {
            isEnabled = true
            // Clear previous logs
            try? "".write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
    
    public func disable() {
        queue.sync {
            isEnabled = false
        }
    }
    
    public func log(_ message: String) {
        guard isEnabled else { return }
        
        queue.async {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let logEntry = "[\(timestamp)] \(message)\n"
            
            if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                handle.seekToEndOfFile()
                if let data = logEntry.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try? logEntry.write(to: self.fileURL, atomically: true, encoding: .utf8)
            }
        }
    }
    
    public func getLogs() -> String {
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }
    
    public func clear() {
        queue.sync {
            try? "".write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
#endif
