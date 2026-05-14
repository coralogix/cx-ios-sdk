//
//  Logger.swift
//

import Foundation

public protocol CXLogger {
    func log(level: LogLevel,
             message: @autoclosure () -> String,
             metadata: [String: Any]?,
             file: String,
             function: String,
             line: Int)
}

public extension CXLogger {
    func log(level: LogLevel,
             _ message: @autoclosure () -> String,
             metadata: [String: Any]? = nil,
             file: String = #fileID,
             function: String = #function,
             line: Int = #line) {
        log(level: level,
            message: message(),
            metadata: metadata,
            file: file,
            function: function,
            line: line)
    }
}

public struct NoopLogger: CXLogger {
    public init() {}
    public func log(level: LogLevel,
                    message: @autoclosure () -> String,
                    metadata: [String: Any]?,
                    file: String,
                    function: String,
                    line: Int) {}
}
