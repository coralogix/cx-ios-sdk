//
//  ErrorContext.swift
//  
//
//  Created by Coralogix DEV TEAM on 08/04/2024.
//

import Foundation
import OpenTelemetrySdk

struct ErrorContext {
    let domain: String
    let code: String
    let localizedDescription: String
    var userInfo: [String: Any]?
    
    let exceptionType: String
    let crashTimestamp: String
    let processName: String
    let applicationIdentifier: String
    var triggeredByThread: Int = 0
    var originalStackTrace: [[String: Any]]?
    let baseAddress: String
    let arch: String
    
    init(otel: SpanDataProtocol) {
        self.domain = otel.getAttribute(forKey: Keys.domain.rawValue) as? String ?? ""
        self.code = otel.getAttribute(forKey: Keys.code.rawValue) as? String ?? ""
        self.localizedDescription = otel.getAttribute(forKey: Keys.localizedDescription.rawValue) as? String ?? ""
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
        
        if let jsonString = otel.getAttribute(forKey: Keys.originalStackTrace.rawValue) as? String,
           let data = Helper.convertJsonStringToArray(jsonString: jsonString) {
            self.originalStackTrace = data
        }
        self.baseAddress = otel.getAttribute(forKey: Keys.baseAddress.rawValue) as? String ?? ""
        self.arch = otel.getAttribute(forKey: Keys.arch.rawValue) as? String ?? ""
    }
    
    func getDictionary() -> [String: Any] {
        if let originalStackTrace = self.originalStackTrace, !originalStackTrace.isEmpty {
            var crashContext = [String: Any]()
            crashContext[Keys.exceptionType.rawValue] = self.exceptionType
            crashContext[Keys.crashTimestamp.rawValue] = self.crashTimestamp
            crashContext[Keys.processName.rawValue] = self.processName
            crashContext[Keys.applicationIdentifier.rawValue] = self.applicationIdentifier
            crashContext[Keys.triggeredByThread.rawValue] = self.triggeredByThread
            crashContext[Keys.baseAddress.rawValue] = self.baseAddress
            crashContext[Keys.arch.rawValue] = self.arch
            if let originalStackTrace = self.originalStackTrace {
                crashContext[Keys.originalStackTrace.rawValue] = originalStackTrace
            }
            return [Keys.crashContext.rawValue: crashContext]
        } else {
            var exceptionContext = [String: Any]()
            exceptionContext[Keys.domain.rawValue] = self.domain
            exceptionContext[Keys.code.rawValue] = self.code
            exceptionContext[Keys.localizedDescription.rawValue] = self.localizedDescription

            if let userInfo = self.userInfo {
                exceptionContext[Keys.userInfo.rawValue] = userInfo
            }
            return [Keys.exceptionContext.rawValue: exceptionContext]
        }
    }
}