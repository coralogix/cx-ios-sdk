//
//  ScreenshotManager.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 04/05/2025.
//
import Foundation
import CoralogixInternal

public class ScreenshotManager {
    private let queue = DispatchQueue(label: "com.coralogix.screenshotManager.queue")
    internal var _page: Int = 0
    internal var _screenshotCount: Int = 0
    
    // Constants
    private let maxScreenShotsPerPage: Int

    public init(maxScreenShotsPerPage: Int = 20) {
        self.maxScreenShotsPerPage = maxScreenShotsPerPage
    }
    
    public var page: Int {
        get { queue.sync { _page } }
    }
    
    public var screenshotCount: Int {
        get { queue.sync { _screenshotCount } }
        set {
            queue.sync { _screenshotCount = newValue }
        }
    }

    func takeScreenshot() {
        queue.sync {
            _screenshotCount += 1
            
            if _screenshotCount % maxScreenShotsPerPage == 0 {
                _page += 1
                Log.d("Page incremented to: \(_page)")
            }
        }
    }
    
    public func resetSession() {
        queue.sync {
            _page = 0
            _screenshotCount = 0
            Log.d("Session reset. New sessionId")
        }
    }
}
