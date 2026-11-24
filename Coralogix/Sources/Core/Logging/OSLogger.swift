//
//  OSLogger.swift
//

import Foundation
import os

public final class OSLogger: CXLogger {
    public static let defaultSubsystem = "com.coralogix.rum"
    public static let defaultCategory = "default"

    /// os_log truncates a single entry beyond an internal size limit (~1 KB on
    /// the legacy path used pre-iOS 14). Messages larger than this fall back to
    /// print() so they survive intact — see `log(...)`.
    private static let maxOSLogMessageBytes = 1024

    private let subsystem: String
    private let category: String
    private let legacyLog: OSLog

    private static let cacheLock = NSLock()
    private static var modernCache: [String: Any] = [:]

    public init(subsystem: String = OSLogger.defaultSubsystem,
                category: String = OSLogger.defaultCategory) {
        self.subsystem = subsystem
        self.category = category
        self.legacyLog = OSLog(subsystem: subsystem, category: category)
    }

    public func log(level: LogLevel,
                    message: @autoclosure () -> String,
                    metadata: [String: Any]?,
                    file: String,
                    function: String,
                    line: Int) {
        let formatted = "\(level.emojiPrefix) \(Self.format(message: message(), metadata: metadata))"

        // os_log clips a single oversized entry (e.g. a crash span's full thread
        // stacks), so for large messages fall back to print(), which has no size
        // limit and keeps the payload intact as one blob. This path is only
        // reachable when logging is enabled (Log.emit gates on isDebug), so it
        // never runs in a release/production app. Normal-sized logs keep going
        // through os_log to retain levels, subsystem/category, and Console.app
        // capture on detached devices.
        if Self.exceedsOSLogLimit(formatted) {
            print(formatted)
            return
        }

        if #available(iOS 14.0, *) {
            let logger = modernLogger()
            switch level {
            case .trace, .debug: logger.debug("\(formatted, privacy: .public)")
            case .info:          logger.info("\(formatted, privacy: .public)")
            case .warning:       logger.notice("\(formatted, privacy: .public)")
            case .error:         logger.error("\(formatted, privacy: .public)")
            case .critical:      logger.fault("\(formatted, privacy: .public)")
            }
        } else {
            os_log("%{public}@", log: legacyLog, type: level.osLogType, formatted)
        }
    }

    @available(iOS 14.0, *)
    private func modernLogger() -> os.Logger {
        let key = "\(subsystem)|\(category)"
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }
        if let existing = Self.modernCache[key] as? os.Logger {
            return existing
        }
        let made = os.Logger(subsystem: subsystem, category: category)
        Self.modernCache[key] = made
        return made
    }

    /// Whether `formatted` is large enough that os_log would truncate it and the
    /// logger should fall back to print(). Extracted so the size policy is testable
    /// without capturing os_log/stdout side effects.
    static func exceedsOSLogLimit(_ formatted: String) -> Bool {
        formatted.utf8.count > maxOSLogMessageBytes
    }

    private static func format(message: String, metadata: [String: Any]?) -> String {
        guard let metadata = metadata, !metadata.isEmpty else { return message }
        let pairs = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return "\(message) [\(pairs)]"
    }
}

private extension LogLevel {
    var osLogType: OSLogType {
        switch self {
        case .trace, .debug: return .debug
        case .info:          return .info
        case .warning:       return .default
        case .error:         return .error
        case .critical:      return .fault
        }
    }

    var emojiPrefix: String {
        switch self {
        case .trace:    return "🟦"
        case .debug:    return "🟪"
        case .info:     return "🟩"
        case .warning:  return "🟨"
        case .error:    return "🟥"
        case .critical: return "💥"
        }
    }
}
