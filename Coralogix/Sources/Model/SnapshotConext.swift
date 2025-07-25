//
//  SnapshotConext.swift
//
//
//  Created by Coralogix Dev Team on 16/06/2024.
//

import Foundation
import CoralogixInternal

public struct SnapshotContext {
    let timestamp: TimeInterval
    let errorCount: Int
    let viewCount: Int
    let actionCount: Int
    let hasRecording: Bool

    init(timestamp: TimeInterval, errorCount: Int, viewCount: Int, actionCount: Int, hasRecording: Bool) {
        self.timestamp = timestamp
        self.errorCount = errorCount
        self.viewCount = viewCount
        self.actionCount = actionCount
        self.hasRecording = hasRecording
    }
    
    func getDictionary() -> [String: Any] {
        var result = [String: Any]()
        result[Keys.timestamp.rawValue] = self.timestamp.milliseconds
        result[Keys.errorCount.rawValue] = self.errorCount
        result[Keys.viewCount.rawValue] = self.viewCount
        result[Keys.actionCount.rawValue] = self.actionCount
        result[Keys.hasRecording.rawValue] = self.hasRecording
        return result
    }
}
