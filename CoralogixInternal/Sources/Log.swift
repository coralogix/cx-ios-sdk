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
    
    /// Logs an error message using the provided `Error` instance.
    ///
    /// This is a convenience method that delegates to `Log.error(_:)`. The error's localized description is always printed, regardless of the debug mode.
    public static func e(_ error: Error) {
        Log.error(error)
    }
    
    /// Logs an error message with a red square prefix, displaying the error's localized description regardless of debug mode.
    ///
    /// - Parameter error: The error to be logged.
    public static func error(_ error: Error) {
        print("🟥 \(error.localizedDescription)")
    }
}
