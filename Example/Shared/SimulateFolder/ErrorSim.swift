//
//  SimError.swift
//  Elastiflix-iOS
//
//  Created by Coralogix DEV TEAM on 08/04/2024.
//

import Foundation
import Coralogix

class ErrorSim {
    static func sendNSException() {
        let userInfo = ["Key": "Value"]
        let exception = NSException(name: NSExceptionName(rawValue: "IllegalFormatError"),
                                    reason: "This is a custom exception",
                                    userInfo: userInfo)
        CoralogixRumManager.shared.sdk.reportError(exception: exception)
    }
    
    static func sendNSError() {
        let userInfo = [NSLocalizedDescriptionKey: "An error occurred"]
        let error = NSError(domain: "YourDomain",
                            code: 0,
                            userInfo: userInfo)
        CoralogixRumManager.shared.sdk.reportError(error: error)
    }
    
    static func sendError() {
        let filename = "file.txt"
        CoralogixRumManager.shared.sdk.reportError(error: CustomError.fileNotFound("File not found: \(filename)"))
    }
    
    static func sendMessageDataError() {
        CoralogixRumManager.shared.sdk.reportError(
            message: "errorcode=500 Im cusom Error",
            data: ["gender": "female", "height": "1.30"])
    }
    
   static func sendMessageStackTraceTypeIsCarshError() {
        CoralogixRumManager.shared.sdk.reportError(
            message: "im custom error",
            stackTrace: [["func1": "line1" , "func2": "line2"]],
            errorType: "5",
            isCrash: Bool.random())
    }
    
    static func sendErrorLog() {
        CoralogixRumManager.shared.sdk.log(severity: CoralogixLogSeverity.error, message: "Im error log", data: ["gender": "male", "height": "1.78"])
    }
    
    static func simulateANR() {
        sleep(10)
    }

    // Simulates a Flutter error with a symbolicated (readable) Dart stack trace.
    // This is the format produced by a non-obfuscated Flutter/Dart app.
    static func sendFlutterSymbolicatedError() {
        let frames: [[String: Any]] = [
            ["functionName": "throwExceptionInDart", "fileName": "package:coralogix_sdk/main.dart", "lineNumber": 134, "columnNumber": 5],
            ["functionName": "_MyAppState.build.<anonymous closure>", "fileName": "package:coralogix_sdk/main.dart", "lineNumber": 121, "columnNumber": 32],
            ["functionName": "_InkResponseState.handleTap", "fileName": "package:flutter/src/material/ink_well.dart", "lineNumber": 1171, "columnNumber": 21],
            ["functionName": "GestureRecognizer.invokeCallback", "fileName": "package:flutter/src/gestures/recognizer.dart", "lineNumber": 344, "columnNumber": 24],
            ["functionName": "TapGestureRecognizer.handleTapUp", "fileName": "package:flutter/src/gestures/tap.dart", "lineNumber": 652, "columnNumber": 11]
        ]
        CoralogixRumManager.shared.sdk.reportError(
            message: "state error try catch",
            stackTrace: frames,
            errorType: "FlutterError",
            stackTraceType: "symbolicated"
        )
    }

    // Simulates a Flutter error with an obfuscated Dart stack trace.
    // This is the format produced when the Flutter app is built with --obfuscate --split-debug-info.
    // Only virtual addresses are available; symbolication requires the app's debug symbols + build_id.
    static func sendFlutterObfuscatedError() {
        CoralogixRumManager.shared.sdk.reportError(
            message: "StateError: state error try catch",
            obfuscatedStackTrace: [
                "0x00000000003da15f",
                "0x000000000022d923",
                "0x000000000025bf87"
            ],
            arch: "arm64",
            buildId: "e4f372b4e5cb2ba87653648d9c509cb1",
            stackTraceType: "obfuscated"
        )
    }
    
    enum CustomError: Error {
        case invalidInput
        case networkError(String)
        case fileNotFound(String)
    }
}

