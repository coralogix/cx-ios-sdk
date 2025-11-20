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
    
    static func sendCustomError() {
        let filename = "file.txt"
        CoralogixRumManager.shared.sdk.reportError(error: CustomError.fileNotFound("File not found: \(filename)"))
    }
    
    static func sendStringError() {
        CoralogixRumManager.shared.sdk.reportError(message: "errorcode=500 Im cusom Error", data: ["gender": "female", "height": "1.30"])
    }
    
    static func simulateANR() {
        sleep(10)
    }
    
    static func sendLog() {
        CoralogixRumManager.shared.sdk.log(severity: CoralogixLogSeverity.warn, message: "Im cusom log", data: ["gender": "male", "height": "1.78"])
    }
    
    enum CustomError: Error {
        case invalidInput
        case networkError(String)
        case fileNotFound(String)
    }
}

