//
//  SessionManager.swift
//
//
//  Created by Coralogix DEV TEAM on 01/05/2024.
//

import Foundation
import CoralogixInternal
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
    private var sessionMetadata: SessionMetadata?
    private var prevSessionMetadata: SessionMetadata?

    private var lastActivityTime: Date?
    private var idleTimer: Timer?
    private let idleInterval: TimeInterval = 15 * 60  // 15 minutes in seconds
    private var errorCount: Int = 0
    private var clickCount: Int = 0
    public var sessionChangedCallback: ((String) -> Void)?
    var lastSnapshotEventTime: Date?
    public var hasRecording: Bool = false

    public init() {
        self.setupSessionMetadata()
        self.setupIdleTimer()
        self.updateActivityTime()
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
    
    public func getSessionMetadata() -> SessionMetadata? {
        if let sessionCreationDate = self.sessionMetadata?.sessionCreationDate,
            self.hasAnHourPassed(since: sessionCreationDate) == true {
            self.setupSessionMetadata()
        }
        return self.sessionMetadata
    }
    
    public func shutdown() {
        self.sessionMetadata = SessionMetadata(sessionId: "",
                                               sessionCreationDate: 0,
                                               keychain: KeychainManager())
        self.idleTimer?.invalidate()
        self.hasRecording = false
    }
    
    public func reset() {
        self.errorCount = 0
        self.clickCount = 0
        self.hasRecording = false
    }
    
    public func getErrorCount() -> Int {
        return errorCount
    }
    
    public func getClickCount() -> Int {
        return clickCount
    }
    
    private func hasAnHourPassed(since timeInterval: TimeInterval) -> Bool {
        let dateFromInterval = Date(timeIntervalSince1970: timeInterval)
        let currentDate = Date()
        let hourInSeconds: TimeInterval = 3600  // Number of seconds in an hour

        // Calculate the difference in seconds between the current date and the date from the interval
        let timeDifference = currentDate.timeIntervalSince(dateFromInterval)

        // Check if this difference is at least an hour
        return timeDifference >= hourInSeconds
    }
    
    private func setupSessionMetadata() {
        self.prevSessionMetadata = self.sessionMetadata
        self.sessionMetadata = SessionMetadata(sessionId: NSUUID().uuidString,
                                               sessionCreationDate: Date().timeIntervalSince1970,
                                               keychain: KeychainManager())
        // Publish the new session Id
        if let sessionId = self.sessionMetadata?.sessionId {
            self.sessionChangedCallback?(sessionId)
        }
    }
    
    private func setupIdleTimer() {
        idleTimer = Timer.scheduledTimer(timeInterval: 60,
                                         target: self,
                                         selector: #selector(checkIdleTime),
                                         userInfo: nil,
                                         repeats: true)
    }
    
    // Call this function every time the monitored function is executed
    func updateActivityTime() {
        lastActivityTime = Date()
        if let lastActivityTime = lastActivityTime {
            Log.d("Activity updated at \(lastActivityTime)")
        }
    }
    
    @objc private func checkIdleTime() {
        guard let lastActivity = lastActivityTime else {
            Log.e("No activity has been recorded yet.")
            return
        }
        
        let now = Date()
        let timeSinceLastActivity = now.timeIntervalSince(lastActivity)
        
        if timeSinceLastActivity > idleInterval {
            self.setupSessionMetadata()
            NotificationCenter.default.post(name: .cxRumNotificationSessionEnded, object: nil)
            Log.d("Function has been idle for 15 minutes.")
        } else {
            let minutes = Int((idleInterval - timeSinceLastActivity) / 60)
            Log.d("Function is active. Idle in approximately \(minutes) minutes.")
        }
    }

    deinit {
        idleTimer?.invalidate()
    }
}
