//
//  ScreenshotContext.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 01/07/2025.
//

import Foundation

public struct ScreenshotContext {
    let screenshotId: String
    let segmentTimestamp: TimeInterval
    var isManual: Bool = false
    
    init(otel: SpanDataProtocol) {
        self.screenshotId = otel.getAttribute(forKey: Keys.screenshotId.rawValue) as? String ?? Keys.undefined.rawValue
        self.segmentTimestamp = otel.getStartTime() ?? Date().timeIntervalSince1970
        if let attribute = otel.getAttribute(forKey: Keys.isManual.rawValue) as? String,
            let isManual = Bool(attribute.description) {
            self.isManual = isManual
        }
    }
    
    func isValid() -> Bool {
        return self.screenshotId != Keys.undefined.rawValue
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.screenshotId.rawValue] = self.screenshotId
        result[Keys.segmentTimestamp.rawValue] = self.segmentTimestamp.milliseconds
        result[Keys.isManual.rawValue] = self.isManual
        return result
    }
}
