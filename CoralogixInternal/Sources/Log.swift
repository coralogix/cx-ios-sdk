//
//  Log.swift
//
//  Created by Coralogix DEV TEAM on 02/04/2024.
//

import Foundation

public class Log {
    public static var isDebug = false

    private static let sharedLock = NSLock()
    private static var _shared: CXLogger = OSLogger()

    public static var shared: CXLogger {
        get {
            sharedLock.lock()
            defer { sharedLock.unlock() }
            return _shared
        }
        set {
            sharedLock.lock()
            defer { sharedLock.unlock() }
            _shared = newValue
        }
    }

    // Emits at `level` if-and-only-if `isDebug` is true. `message` is only
    // invoked after the gate, so disabled levels do not evaluate the closure.
    private static func emit(level: LogLevel,
                             message: () -> String,
                             file: String,
                             function: String,
                             line: Int) {
        guard isDebug else { return }
        shared.log(level: level,
                   message: message(),
                   metadata: nil,
                   file: file,
                   function: function,
                   line: line)
    }

    // MARK: - Debug

    public static func d(_ message: @autoclosure () -> String,
                         file: String = #fileID,
                         function: String = #function,
                         line: Int = #line) {
        emit(level: .debug, message: message, file: file, function: function, line: line)
    }

    public static func debug(_ message: @autoclosure () -> String,
                             file: String = #fileID,
                             function: String = #function,
                             line: Int = #line) {
        emit(level: .debug, message: message, file: file, function: function, line: line)
    }

    // MARK: - Trace

    public static func t(_ message: @autoclosure () -> String,
                         file: String = #fileID,
                         function: String = #function,
                         line: Int = #line) {
        emit(level: .trace, message: message, file: file, function: function, line: line)
    }

    public static func trace(_ message: @autoclosure () -> String,
                             file: String = #fileID,
                             function: String = #function,
                             line: Int = #line) {
        emit(level: .trace, message: message, file: file, function: function, line: line)
    }

    // MARK: - Warning

    public static func w(_ message: @autoclosure () -> String,
                         file: String = #fileID,
                         function: String = #function,
                         line: Int = #line) {
        emit(level: .warning, message: message, file: file, function: function, line: line)
    }

    public static func warning(_ message: @autoclosure () -> String,
                               file: String = #fileID,
                               function: String = #function,
                               line: Int = #line) {
        emit(level: .warning, message: message, file: file, function: function, line: line)
    }

    // MARK: - Error

    public static func e(_ message: @autoclosure () -> String = "",
                         _ error: Error? = nil,
                         file: String = #fileID,
                         function: String = #function,
                         line: Int = #line) {
        emit(level: .error,
             message: { combine(message: message(), error: error) },
             file: file,
             function: function,
             line: line)
    }

    public static func error(_ message: @autoclosure () -> String = "",
                             _ error: Error? = nil,
                             file: String = #fileID,
                             function: String = #function,
                             line: Int = #line) {
        emit(level: .error,
             message: { combine(message: message(), error: error) },
             file: file,
             function: function,
             line: line)
    }

    public static func e(_ error: Error,
                         file: String = #fileID,
                         function: String = #function,
                         line: Int = #line) {
        Log.error(error, file: file, function: function, line: line)
    }

    public static func error(_ error: Error,
                             file: String = #fileID,
                             function: String = #function,
                             line: Int = #line) {
        emit(level: .error,
             message: { error.localizedDescription },
             file: file,
             function: function,
             line: line)
    }

    private static func combine(message: String, error: Error?) -> String {
        guard let error = error else { return message }
        if message.isEmpty { return error.localizedDescription }
        return "\(message)\ndetails:\n\(error.localizedDescription)"
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
