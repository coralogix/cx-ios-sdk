//
//  SessionManager.swift
//
//
//  Created by Coralogix DEV TEAM on 01/05/2024.
//

import Foundation
import CoralogixInternal

#if canImport(UIKit)
import UIKit
#endif
/**
 * When Is a New Session Created?
 *
 * A new session is created under the following circumstances:
 *
 * 1. **Idle Timeout**
 *    If the time since the last recorded activity exceeds the idle interval (15 minutes),
 *    the `setupSessionMetadata` method is called from `checkIdleTime`.
 *
 *    ```swift
 *    if timeSinceLastActivity > idleInterval {
 *        self.setupSessionMetadata()
 *        Log.d("Function has been idle for 15 minutes.")
 *    }
 *    ```
 *
 * 2. **An Hour Has Passed**
 *    The `getSessionMetadata` method checks if an hour has passed since the current session was created.
 *    If so, it triggers `setupSessionMetadata` to create a new session.
 *
 *    ```swift
 *    if let sessionCreationDate = self.sessionMetadata?.sessionCreationDate,
 *       self.hasAnHourPassed(since: sessionCreationDate) {
 *        self.setupSessionMetadata()
 *    }
 *    ```
 *
 * 3. **Explicit Session Management**
 *    The `setupSessionMetadata` method can also be invoked explicitly, such as during a reset or other custom logic.
 */

public class SessionManager {
    internal var sessionMetadata: SessionMetadata?
    private var prevSessionMetadata: SessionMetadata?

    internal var lastActivity = Date()
    private let idleInterval: TimeInterval = 15 * 60  // 15 minutes in seconds
    private var errorCount: Int = 0
    private var clickCount: Int = 0
    private let countersLock = NSLock()
    /// Serializes session-rotation read/write. NSRecursiveLock because
    /// `getSessionMetadata` → `setupSessionMetadata` and `updateActivityTime`
    /// → `setupSessionMetadata` both re-lock from the same thread. Network
    /// instrumentation reads run on URLSession delegate threads, so concurrent
    /// reads on stale sessions need to serialize to avoid two rotations
    /// producing two different new session IDs.
    private let sessionLock = NSRecursiveLock()
    public var sessionChangedCallback: ((String) -> Void)?
    public var sessionEndedCallback: (() -> Void)?
    /// Fired alongside `sessionChangedCallback` on every session rotation. Kept as a separate
    /// property so the sampling-reroll path cannot accidentally clobber the existing
    /// SessionReplay listener that owns `sessionChangedCallback`. Internal-only — host apps
    /// have no use for setting this, and a public slot would invite accidental clobber.
    internal var samplingReevaluationCallback: ((String) -> Void)?
    public var hasRecording: Bool = false
    
    public var lastSnapshotEventTime: Date?
    public var isIdle: Bool {
        let timeSinceLastActivity = Date().timeIntervalSince(self.lastActivity)
        return timeSinceLastActivity > idleInterval
    }
    
    public init() {
        self.setupSessionMetadata()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidBecomeActiveNotification),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleTapNotification(notification:)),
                                               name: .cxRumNotificationUserActions,
                                               object: nil)
    }
    
    public func doesSessionHasRecording() -> Bool {
        return self.hasRecording
    }
    
    public func incrementErrorCounter() {
        countersLock.lock()
        defer { countersLock.unlock() }
        errorCount += 1
    }

    public func decrementErrorCounter() {
        countersLock.lock()
        defer { countersLock.unlock() }
        if errorCount > 0 {
            errorCount -= 1
        }
    }
    
    public func incrementClickCounter() {
        countersLock.lock()
        defer { countersLock.unlock() }
        clickCount += 1
    }
    
    public func getPrevSessionMetadata() -> SessionMetadata? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return self.prevSessionMetadata
    }
    
    public func getErrorCount() -> Int {
        countersLock.lock()
        defer { countersLock.unlock() }
        return errorCount
    }
    
    public func getClickCount() -> Int {
        countersLock.lock()
        defer { countersLock.unlock() }
        return clickCount
    }
    
    public func getSessionMetadata() -> SessionMetadata? {
        sessionLock.lock()
        defer { sessionLock.unlock() }

        // Rotation is purely time-based: if the session is older than 1h, rotate
        // regardless of activity state. Idle state gates *export* (see
        // CoralogixExporter.export), not rotation — the two concerns are
        // independent. The previous `isIdle == false` guard meant an idle session
        // could persist for days and then leak its stale ID onto the next
        // emitted span (24h-session bug).
        if let sessionCreationDate = self.sessionMetadata?.sessionCreationDate,
           self.hasAnHourPassed(since: sessionCreationDate) {
            self.sessionEndedCallback?()
            self.setupSessionMetadata()
        }
        return self.sessionMetadata
    }
    
    public func shutdown() {
        self.sessionMetadata = SessionMetadata(sessionId: "",
                                               sessionCreationDate: 0,
                                               using: KeychainManager())
        self.reset()
    }
    
    public func reset() {
        countersLock.lock()
        self.errorCount = 0
        self.clickCount = 0
        countersLock.unlock()
        self.hasRecording = false
    }
    
    @objc private func appDidBecomeActiveNotification(notification: Notification) {
        self.updateActivityTime()
    }
    
    @objc func handleTapNotification(notification: Notification) {
        self.updateActivityTime()
    }
    
    private func hasAnHourPassed(since timeInterval: TimeInterval) -> Bool {
        // If the time is 0, treat it as invalid or "not passed"
        guard timeInterval > 0 else {
            return false
        }
        
        let dateFromInterval = Date(timeIntervalSince1970: timeInterval)
        let currentDate = Date()
        let hourInSeconds: TimeInterval = 3600  // Number of seconds in an hour

        // Calculate the difference in seconds between the current date and the date from the interval
        let timeDifference = currentDate.timeIntervalSince(dateFromInterval)

        // Check if this difference is at least an hour
        return timeDifference >= hourInSeconds
    }
    
    internal func setupSessionMetadata() {
        sessionLock.lock()
        defer { sessionLock.unlock() }

        self.prevSessionMetadata = self.sessionMetadata
        self.sessionMetadata = SessionMetadata(sessionId: UUID().uuidString.lowercased(),
                                               sessionCreationDate: Date().timeIntervalSince1970,
                                               using: KeychainManager())
        // Reset snapshot-throttle so the fresh session can emit its first
        // snapshot immediately; otherwise the previous session's timestamp
        // would suppress the new session's first non-error/non-navigation
        // event for up to 60s (see CxRumBuilder.buildSnapshotContextIfNeeded).
        self.lastSnapshotEventTime = nil

        if let sessionId = self.sessionMetadata?.sessionId {
            self.sessionChangedCallback?(sessionId)
            self.samplingReevaluationCallback?(sessionId)
        }
    }

    internal func updateActivityTime() {
        sessionLock.lock()
        defer { sessionLock.unlock() }

        if isIdle {
            Log.d("[SDK] transitioning from idle to active state")
            self.sessionEndedCallback?()
            setupSessionMetadata()
        }
        lastActivity = Date()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self,
                                            name: UIApplication.didBecomeActiveNotification,
                                            object: nil)
        
        NotificationCenter.default.removeObserver(self,
                                                  name: .cxRumNotificationUserActions,
                                                  object: nil)
    }
}
