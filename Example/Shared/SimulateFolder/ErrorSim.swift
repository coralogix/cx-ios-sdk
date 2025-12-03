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
    
    enum CustomError: Error {
        case invalidInput
        case networkError(String)
        case fileNotFound(String)
    }
}

