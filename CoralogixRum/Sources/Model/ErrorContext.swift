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
    
    init(otel: SpanData) {
        self.domain = otel.attributes[Keys.domain.rawValue]?.description ?? ""
        self.code = otel.attributes[Keys.code.rawValue]?.description ?? ""
        self.localizedDescription = otel.attributes[Keys.localizedDescription.rawValue]?.description ?? ""
        if let jsonString = otel.attributes[Keys.userInfo.rawValue]?.description,
           let dict = Helper.convertJsonStringToDict(jsonString: jsonString) {
            self.userInfo = dict
        }
        
        self.exceptionType = otel.attributes[Keys.exceptionType.rawValue]?.description ?? ""
        self.crashTimestamp = otel.attributes[Keys.crashTimestamp.rawValue]?.description ?? ""
        self.processName = otel.attributes[Keys.processName.rawValue]?.description ?? ""
        self.applicationIdentifier = otel.attributes[Keys.applicationIdentifier.rawValue]?.description ?? ""
        if let triggeredByThread = otel.attributes[Keys.triggeredByThread.rawValue]?.description {
            self.triggeredByThread = Int(triggeredByThread) ?? -1
        }
        
        if let jsonString = otel.attributes[Keys.originalStackTrace.rawValue]?.description,
           let data = Helper.convertJsonStringToArray(jsonString: jsonString) {
            self.originalStackTrace = data
        }
        self.baseAddress = otel.attributes[Keys.baseAddress.rawValue]?.description ?? ""
        self.arch = otel.attributes[Keys.arch.rawValue]?.description ?? ""
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
