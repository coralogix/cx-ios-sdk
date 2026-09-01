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
    
    /// Returns a reservation, identified by the location it was minted as.
    ///
    /// The counter is a single high-water mark, so only the most recent reservation can be
    /// returned: stepping it back when a newer capture has already taken an index would reissue
    /// that index, and `generateFileName` would then overwrite a frame that already shipped.
    /// A mismatch means a newer capture is in flight, so the slot is left burned — a gap is
    /// recoverable, a collision is not.
    public func revertScreenshotCounter(for location: ScreenshotLocation) {
        queue.sync(flags: .barrier) {
            guard page == location.page, screenshotCount == location.segmentIndex else {
                return
            }
            revertLocked()
        }
    }

    /// Unconditional revert. No caller inside the SDK reaches this any more — every capture
    /// knows the page and segment index it reserved — and its only remaining effect is the
    /// counter collision `revertScreenshotCounter(for:)` exists to prevent.
    @available(*, deprecated, message: "Use revertScreenshotCounter(for:), which cannot roll back a reservation a newer capture already took.")
    public func revertScreenshotCounter() {
        queue.sync(flags: .barrier) {
            revertLocked()
        }
    }

    /// Caller must hold the barrier.
    private func revertLocked() {
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
