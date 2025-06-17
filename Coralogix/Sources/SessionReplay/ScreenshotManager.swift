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
    internal var _page: Int = 0
    internal var _screenshotCount: Int = 0
    internal var _screenshotId: String = UUID().uuidString.lowercased()
    private let maxScreenshotsPerPage: Int
    public static let defaultMaxScreenShotsPerPage = 20

    public init(maxScreenShotsPerPage: Int = ScreenshotManager.defaultMaxScreenShotsPerPage) {
        self.maxScreenshotsPerPage = maxScreenShotsPerPage
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(resetSession(notification:)),
                                               name: .cxRumNotificationSessionEnded, object: nil)
        
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .cxRumNotificationSessionEnded, object: nil)
    }
    
    public var nextScreenshotLocation: ScreenshotLocation {
        queue.sync(flags: .barrier) {
            _screenshotCount += 1
            
            if _screenshotCount > maxScreenshotsPerPage {
                                  
                _page += 1
                _screenshotCount = 1
                Log.d("Page incremented to: \(_page)")
            }
            
            return ScreenshotLocation(
                segmentIndex: _screenshotCount,
                page: _page,
                screenshotId: _screenshotId
            )
        }
    }

    @objc func resetSession(notification: Notification) {
        queue.sync(flags: .barrier) {
            _page = 0
            _screenshotCount = 0
            _screenshotId = UUID().uuidString.lowercased()
        }
    }
}
