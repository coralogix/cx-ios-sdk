//
//  OSLogger.swift
//

import Foundation
import os

public final class OSLogger: Logger {
    public static let defaultSubsystem = "com.coralogix.rum"
    public static let defaultCategory = "default"

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
        let formatted = Self.format(message: message(), metadata: metadata)

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

        print("\(level.emojiPrefix) \(formatted)")
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
