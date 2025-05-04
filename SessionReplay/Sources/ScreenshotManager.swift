//
//  ScreenshotManager.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 04/05/2025.
//
import Foundation
import CoralogixInternal

class ScreenshotManager {
    internal var page: Int = 0
    internal var screenshotCount: Int = 0
    
    // Constants
    private var sessionStartTimestamp: Date = Date()
    private var maxScreenShotsPerPage: Int = 5

    func takeScreenshot() {
        screenshotCount += 1

        if screenshotCount % maxScreenShotsPerPage == 0 {
            page += 1
            Log.d("Page incremented to: \(page)")
        }
    }
    
    public func resetSession() {
        page = 0
        screenshotCount = 0
        sessionStartTimestamp = Date()
        Log.d("Session reset. New sessionId")
    }
}
