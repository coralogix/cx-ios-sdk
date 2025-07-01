//
//  ScreenshotContext.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 01/07/2025.
//

import Foundation

public struct ScreenshotContext {
    let screenshotId: String
    let page: Int
    let segmentTimestamp: TimeInterval
    var isManual: Bool = false
    
    init(otel: SpanDataProtocol) {
        self.screenshotId = otel.getAttribute(forKey: Keys.screenshotId.rawValue) as? String ?? Keys.undefined.rawValue
        let page = otel.getAttribute(forKey: Keys.page.rawValue) as? String ?? "0"
        if let pageInt = Int(page) {
            self.page = pageInt
        } else {
            Log.w("Invalid page value: \(page), defaulting to 0")
            self.page = 0
        }
        self.segmentTimestamp = otel.getStartTime() ?? Date().timeIntervalSince1970
        if let attribute = otel.getAttribute(forKey: Keys.isManual.rawValue) as? String {
            self.isManual = Bool(attribute) ?? false
        }
    }
    
    func isValid() -> Bool {
        return self.screenshotId != Keys.undefined.rawValue
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.screenshotId.rawValue] = self.screenshotId
        result[Keys.segmentTimestamp.rawValue] = self.segmentTimestamp.milliseconds
        result[Keys.page.rawValue] = self.page
        result[Keys.isManual.rawValue] = self.isManual
        return result
    }
}
