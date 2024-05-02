//
//  SessionManager.swift
//
//
//  Created by Coralogix DEV TEAM on 01/05/2024.
//

import Foundation

public class SessionManager {
    private var sessionMetadata: SessionMetadata?
    private var prevSessionMetadata: SessionMetadata?

    private var lastActivityTime: Date?
    private var idleTimer: Timer?
    private let idleInterval: TimeInterval = 15 * 60  // 15 minutes in seconds
    
    init() {
        self.setupSessionMetadata()
        self.setupIdleTimer()
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
        self.sessionMetadata = SessionMetadata(sessionId: "", sessionCreationDate: 0)
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
                                               sessionCreationDate: Date().timeIntervalSince1970)
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
        Log.d("Activity updated at \(lastActivityTime!)")
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
