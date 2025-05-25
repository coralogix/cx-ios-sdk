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
}
