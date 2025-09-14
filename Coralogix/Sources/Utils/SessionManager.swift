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
 *        NotificationCenter.default.post(name: .cxRumNotificationSessionEnded, object: nil)
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
    public var sessionChangedCallback: ((String) -> Void)?
    public var hasRecording: Bool = false
    
    public var hasInitializedMobileVitals = false
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
    
    public func doesSessionhasRecording() -> Bool {
        return self.hasRecording
    }
    
    public func incrementErrorCounter() {
        errorCount += 1
    }
    
    public func incrementClickCounter() {
        clickCount += 1
    }
    
    public func getPrevSessionMetadata() -> SessionMetadata? {
        return self.prevSessionMetadata
    }
    
    public func getErrorCount() -> Int {
        return errorCount
    }
    
    public func getClickCount() -> Int {
        return clickCount
    }
    
    public func getSessionMetadata() -> SessionMetadata? {
        if let sessionCreationDate = self.sessionMetadata?.sessionCreationDate,
           self.isIdle == false,
            self.hasAnHourPassed(since: sessionCreationDate) == true {
            self.setupSessionMetadata()
            NotificationCenter.default.post(name: .cxRumNotificationSessionEnded, object: nil)
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
        self.errorCount = 0
        self.clickCount = 0
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
        self.prevSessionMetadata = self.sessionMetadata
        self.sessionMetadata = SessionMetadata(sessionId: UUID().uuidString.lowercased(),
                                               sessionCreationDate: Date().timeIntervalSince1970,
                                               using: KeychainManager())

        if let sessionId = self.sessionMetadata?.sessionId {
            self.sessionChangedCallback?(sessionId)
        }
    }
    
    internal func updateActivityTime() {
        if isIdle {
            Log.d("[SDK] transitioning from idle to active state")
            setupSessionMetadata()
            NotificationCenter.default.post(name: .cxRumNotificationSessionEnded, object: nil)
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
