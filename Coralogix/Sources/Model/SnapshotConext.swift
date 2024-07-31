//
//  SnapshotConext.swift
//
//
//  Created by Coralogix Dev Team on 16/06/2024.
//

import Foundation

public struct SnapshotConext {
    let timestemp: TimeInterval
    let errorCount: Int
    let viewCount: Int
    
    static func getSnapshot(otel: SpanDataProtocol) -> SnapshotConext? {
        if let jsonString = otel.getAttribute(forKey: Keys.snapshotContext.rawValue) as? String,
           let dict = Helper.convertJsonStringToDict(jsonString: jsonString) {
            let timestemp = dict[Keys.timestamp.rawValue] as? TimeInterval ?? Date().timeIntervalSince1970
            let errorCount = dict[Keys.errorCount.rawValue] as? Int ?? 0
            let viewCount = dict[Keys.viewCount.rawValue] as? Int ?? 0
            return SnapshotConext(timestemp: timestemp, errorCount: errorCount, viewCount: viewCount)
        }
        return nil
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.timestamp.rawValue] = self.timestemp.milliseconds
        result[Keys.errorCount.rawValue] = self.errorCount
        result[Keys.viewCount.rawValue] = self.viewCount
        return result
    }
}
