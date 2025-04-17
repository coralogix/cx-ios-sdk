//
//  SnapshotConext.swift
//
//
//  Created by Coralogix Dev Team on 16/06/2024.
//

import Foundation
import CoralogixInternal

public struct SnapshotConext {
    let timestemp: TimeInterval
    let errorCount: Int
    let viewCount: Int
    let clickCount: Int
    let hasRecording: Bool
    
    static func getSnapshot(otel: SpanDataProtocol, sessionManager: SessionManager?) -> SnapshotConext? {
        if let jsonString = otel.getAttribute(forKey: Keys.snapshotContext.rawValue) as? String,
           let dict = Helper.convertJsonStringToDict(jsonString: jsonString) {
            let timestemp = dict[Keys.timestamp.rawValue] as? TimeInterval ?? Date().timeIntervalSince1970
            let errorCount = dict[Keys.errorCount.rawValue] as? Int ?? 0
            let viewCount = dict[Keys.viewCount.rawValue] as? Int ?? 0
            let clickCount = dict[Keys.clickCount.rawValue] as? Int ?? 0
            
            var hasRecording = false
            if let sessionManager = sessionManager {
                hasRecording = sessionManager.hasRecording
            }
            
            return SnapshotConext(timestemp: timestemp,
                                  errorCount: errorCount,
                                  viewCount: viewCount,
                                  clickCount: clickCount,
                                  hasRecording: hasRecording)
        }
        return nil
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.timestamp.rawValue] = self.timestemp.milliseconds
        result[Keys.errorCount.rawValue] = self.errorCount
        result[Keys.viewCount.rawValue] = self.viewCount
        result[Keys.clickCount.rawValue] = self.clickCount
        result[Keys.hasRecording.rawValue] = self.hasRecording
        return result
    }
}
