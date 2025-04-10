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
//        CoralogixRum.shared.reportError(exception: exception)
    }
    
    static func sendNSError() {
        let userInfo = [NSLocalizedDescriptionKey: "An error occurred"]
        let error = NSError(domain: "YourDomain",
                            code: 0,
                            userInfo: userInfo)
//        CoralogixRum.shared.reportError(error: error)
    }
    
    static func sendCustomError() {
        let filename = "file.txt"
//        CoralogixRum.shared.reportError(error: CustomError.fileNotFound("File not found: \(filename)"))
    }
    
    static func sendStringError() {
//        CoralogixRum.shared.reportError(message: "errorcode=500 Im cusom Error", data: ["gender": "female", "height": "1.30"])
    }
    
    static func simulateANR() {
        sleep(10)
    }
    
    static func sendStringStacktraceError() {
        let stackTrace = """
#0      throwExceptionInDart (package:coralogix_sdk/main.dart:134:5)
#1      _MyAppState.build.<anonymous closure> (package:coralogix_sdk/main.dart:121:32)
#2      _InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1171:21)
#3      GestureRecognizer.invokeCallback (package:flutter/src/gestures/recognizer.dart:344:24)
#4      TapGestureRecognizer.handleTapUp (package:flutter/src/gestures/tap.dart:652:11)
#5      BaseTapGestureRecognizer._checkUp (package:flutter/src/gestures/tap.dart:309:5)
#6      BaseTapGestureRecognizer.acceptGesture (package:flutter/src/gestures/tap.dart:279:7)
#7      GestureArenaManager.sweep (package:flutter/src/gestures/arena.dart:167:27)
#8      GestureBinding.handleEvent (package:flutter/src/gestures/binding.dart:499:20)
#9      GestureBinding.dispatchEvent (package:flutter/src/gestures/binding.dart:475:22)
#10     RendererBinding.dispatchEvent (package:flutter/src/rendering/binding.dart:425:11)
#11     GestureBinding.<…>
"""
//        CoralogixRum.shared.reportError(message: "flutter error", stackTrace: stackTrace)
    }
    
    static func sendLog() {
//        CoralogixRum.shared.log(severity: CoralogixLogSeverity.warn, message: "Im cusom log", data: ["gender": "male", "height": "1.78"])
    }
    
    enum CustomError: Error {
        case invalidInput
        case networkError(String)
        case fileNotFound(String)
    }
}

