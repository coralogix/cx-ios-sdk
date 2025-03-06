//
//  ErrorContext.swift
//  
//
//  Created by Coralogix DEV TEAM on 08/04/2024.
//

import Foundation

struct ErrorContext {
    let domain: String
    let code: String
    let errorMessage: String
    var userInfo: [String: Any]?
    let errorType: String
    let exceptionType: String
    let crashTimestamp: String
    let processName: String
    let applicationIdentifier: String
    var triggeredByThread: Int = 0
    var threads: [[[String: Any]]]?
    var stackTrace: [[String: Any]]?
    let baseAddress: String
    let arch: String
    let eventType: String
    
    init(otel: SpanDataProtocol) {
        self.domain = otel.getAttribute(forKey: Keys.domain.rawValue) as? String ?? ""
        self.code = otel.getAttribute(forKey: Keys.code.rawValue) as? String ?? ""
        self.errorMessage = otel.getAttribute(forKey: Keys.errorMessage.rawValue) as? String ?? ""
        if let jsonString = otel.getAttribute(forKey: Keys.userInfo.rawValue) as? String,
           let dict = Helper.convertJsonStringToDict(jsonString: jsonString) {
            self.userInfo = dict
        }
        
        self.exceptionType = otel.getAttribute(forKey: Keys.exceptionType.rawValue) as? String ?? ""
        self.crashTimestamp = otel.getAttribute(forKey: Keys.crashTimestamp.rawValue) as? String ?? ""
        self.processName = otel.getAttribute(forKey: Keys.processName.rawValue) as? String ?? ""
        self.applicationIdentifier = otel.getAttribute(forKey: Keys.applicationIdentifier.rawValue) as? String ?? ""
        if let triggeredByThread = otel.getAttribute(forKey: Keys.triggeredByThread.rawValue) as? String {
            self.triggeredByThread = Int(triggeredByThread) ?? -1
        }
    
        if let jsonString = otel.getAttribute(forKey: Keys.stackTrace.rawValue) as? String,
           let stackTrace = Helper.convertJsonStringToArray(jsonString: jsonString) {
            self.stackTrace = stackTrace
        }
        
        if let jsonString = otel.getAttribute(forKey: Keys.threads.rawValue) as? String,
           let arrayOfTreadsDictJsonString = Helper.convertJsonStringToArrayOfStrings(jsonString: jsonString) {
            self.threads?.removeAll()
            self.threads = [[[String: Any]]]()
            
            for threadJsonString in arrayOfTreadsDictJsonString {
                if let data = Helper.convertJsonStringToArray(jsonString: threadJsonString) {
                    self.threads?.append(data)
                }
            }
        }
        self.baseAddress = otel.getAttribute(forKey: Keys.baseAddress.rawValue) as? String ?? ""
        self.arch = otel.getAttribute(forKey: Keys.arch.rawValue) as? String ?? ""
        self.eventType = otel.getAttribute(forKey: Keys.mobileVitalsType.rawValue) as? String ?? ""
        self.errorType = otel.getAttribute(forKey: Keys.errorType.rawValue) as? String ?? ""
    }
    
    func getDictionary() -> [String: Any] {
        var errorContext = [String: Any]()

        if let threads = self.threads, !threads.isEmpty {
            errorContext[Keys.exceptionType.rawValue] = self.exceptionType
            errorContext[Keys.crashTimestamp.rawValue] = self.crashTimestamp
            errorContext[Keys.processName.rawValue] = self.processName
            errorContext[Keys.applicationIdentifier.rawValue] = self.applicationIdentifier
            errorContext[Keys.triggeredByThread.rawValue] = self.triggeredByThread
            errorContext[Keys.baseAddress.rawValue] = self.baseAddress
            errorContext[Keys.arch.rawValue] = self.arch
            if let threads = self.threads {
                errorContext[Keys.threads.rawValue] = threads
            }
            errorContext[Keys.isCrash.rawValue] = true
            errorContext[Keys.errorMessage.rawValue] = self.exceptionType
        } else {
            if !self.domain.isEmpty {
                errorContext[Keys.domain.rawValue] = self.domain
            }
            
            if !self.code.isEmpty {
                errorContext[Keys.code.rawValue] = self.code
            }
            
            if !self.errorMessage.isEmpty {
                errorContext[Keys.errorMessage.rawValue] = self.errorMessage
            }

            if let userInfo = self.userInfo {
                errorContext[Keys.userInfo.rawValue] = userInfo
            }
            
            if let stackTrace = self.stackTrace {
                errorContext[Keys.originalStackTrace.rawValue] = stackTrace
            }
            
            if !self.errorType.isEmpty {
                errorContext[Keys.errorType.rawValue] = errorType
            }
            
            errorContext[Keys.isCrash.rawValue] = false
            
            if !self.eventType.isEmpty {
                errorContext[Keys.eventType.rawValue] = eventType
            }
        }
        return errorContext
    }
}
