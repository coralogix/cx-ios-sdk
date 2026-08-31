//
//  ScreenshotManager.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 04/05/2025.
//
import Foundation
import CoralogixInternal

public struct ScreenshotLocation {
    public let segmentIndex: Int
    public let page: Int
    public let screenshotId: String
    
    public func toProperties() -> [String: Any] {
        return [
            Keys.screenshotId.rawValue: screenshotId,
            Keys.page.rawValue: page,
            Keys.segmentIndex.rawValue: segmentIndex
        ]
    }
}

public class ScreenshotManager {
    private let queue = DispatchQueue(label: Keys.queueScreenshotManager.rawValue, attributes: .concurrent)
    internal var page: Int = 0
    internal var screenshotCount: Int = 0
    internal var screenshotId: String = UUID().uuidString.lowercased()
    private let maxScreenshotsPerPage: Int
    public static let defaultMaxScreenShotsPerPage = 20

    public init(maxScreenShotsPerPage: Int = ScreenshotManager.defaultMaxScreenShotsPerPage) {
        self.maxScreenshotsPerPage = maxScreenShotsPerPage
    }
    
    public var nextScreenshotLocation: ScreenshotLocation {
        queue.sync(flags: .barrier) {
            screenshotCount += 1
            
            if screenshotCount > maxScreenshotsPerPage {
                                  
                page += 1
                screenshotCount = 1
            }
            
            return ScreenshotLocation(
                segmentIndex: screenshotCount,
                page: page,
                screenshotId: screenshotId
            )
        }
    }
    
    public func revertScreenshotCounter() {
        queue.sync(flags: .barrier) {
            screenshotCount -= 1
            
            if screenshotCount < 1 {
                // Step back a page, down to page 0 — the first page is 0, not 1, so stopping at 1
                // would strand the counter a whole page ahead of the frames that shipped.
                if page > 0 {
                    page -= 1
                    screenshotCount = maxScreenshotsPerPage
                } else {
                    screenshotCount = 0
                }
            }
        }
    }
    
    public func printDebugInfo() {
        // Screenshot manager state: page \(page), count \(screenshotCount)
    }

    public func reset() {
        queue.sync(flags: .barrier) {
            page = 0
            screenshotCount = 0
            screenshotId = UUID().uuidString.lowercased()
        }
    }
}
