//
//  Log.swift
//
//  Created by Coralogix DEV TEAM on 02/04/2024.
//

import Foundation

var isDebug = true

class Log {
    internal static func d(_ message: String) {
        debug(message)
    }
    
    internal static func debug(_ message: String) {
        if isDebug {
            print("🟪 \(message)")
        }
    }
    
    // MARK: - Trace
    
    internal static func t(_ message: String) {
        trace(message)
    }
    
    internal static func trace(_ message: String) {
        if isDebug {
            print("🟦 \(message)")
        }
    }
    
    // MARK: - Warning

    internal static func w(_ message: String) {
        warning(message)
    }
    
    internal static func warning(_ message: String) {
        if isDebug {
            print("🟨 \(message)")
        }
    }
    
    // MARK: - Error

    internal static func e(_ message: String = "", _ error: Error? = nil) {
        Log.error(message, error)
    }
    
    internal static func error(_ message: String = "", _ error: Error? = nil) {
        if isDebug {
            var description = message
            if let error = error {
                description = "\(description)\ndetails:\n\(error.localizedDescription)"
            }
            print("🟥 \(description)")
        }
    }
    
    internal static func e(_ error: Error) {
        Log.error(error)
    }
    
    internal static func error(_ error: Error) {
        if isDebug {
            print("🟥 \(error.localizedDescription)")
        }
    }
}
