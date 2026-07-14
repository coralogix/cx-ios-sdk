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
    /// Serializes session-rotation read/write. Network instrumentation reads
    /// run on URLSession delegate threads, so concurrent reads on stale sessions
    /// need to serialize to avoid two rotations producing two different new
    /// session IDs. Kept as `NSRecursiveLock` defensively — callers must drop
    /// the lock before invoking callbacks (see `setupSessionMetadata`), so no
    /// recursion is intended on this path, but recursion-safe semantics protect
    /// against future regressions.
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

    /// Key/value pairs to record on a span for the current and previous session.
    ///
    /// CRITICAL: routes through `getSessionMetadata()` so the 1-hour rotation check fires
    /// at span-emission time. Direct `self.sessionMetadata` reads bypass rotation and
    /// produce stale `session_id`s on every span (the 24h-session bug). Both `Span` and
    /// `SpanBuilder` call sites should iterate this list rather than hand-rolling the
    /// attribute writes — keeps the rotation invariant and the prev-session breadcrumbs
    /// in one place.
    ///
    /// Two-phase to keep both invariants:
    ///   1. Trigger rotation first via `getSessionMetadata()` (which releases the lock
    ///      before firing any rotation callbacks — see `setupSessionMetadata`).
    ///   2. Briefly re-acquire the lock to snapshot current + prev together so a
    ///      concurrent rotation can't wedge between them and produce a span where
    ///      `prev_session_id` equals the just-emitted `session_id`.
    ///
    /// Returns an empty array when no current session is available; callers can still
    /// emit the span — only the session attributes are skipped.
    func sessionSpanAttributes() -> [(key: String, value: String)] {
        _ = getSessionMetadata()

        sessionLock.lock()
        let current = self.sessionMetadata
        let prev = self.prevSessionMetadata
        sessionLock.unlock()

        var attrs: [(key: String, value: String)] = []
        if let current {
            attrs.append((Keys.sessionId.rawValue, current.sessionId))
            attrs.append((Keys.sessionCreationDate.rawValue, String(Int(current.sessionCreationDate))))
        }
        if let prev {
            if let prevPid = prev.oldPid {
                attrs.append((Keys.prevPid.rawValue, prevPid))
            }
            if let prevSessionId = prev.oldSessionId {
                attrs.append((Keys.prevSessionId.rawValue, prevSessionId))
            }
            if let prevCreation = prev.oldSessionTimeInterval {
                attrs.append((Keys.prevSessionCreationDate.rawValue, String(Int(prevCreation))))
            }
        }
        return attrs
    }

    /// Session-identity attributes for the session that was live in the *previous*
    /// process launch, recovered from the keychain into `sessionMetadata.old*` at
    /// init (before the keychain was overwritten with this launch's identity).
    /// Empty when there is no prior launch on record.
    ///
    /// Crash instrumentation overrides the crash span's `session_id` /
    /// `session_creation_date` with these: a crash captured on relaunch belongs to
    /// the session that actually crashed, not the freshly-created one. This is the
    /// only in-memory copy of the crashed session's identity — the keychain itself
    /// already holds the current launch's session by the time crashes are processed.
    func lastLaunchSessionSpanAttributes() -> [(key: String, value: String)] {
        sessionLock.lock()
        let oldSessionId = self.sessionMetadata?.oldSessionId
        let oldCreationDate = self.sessionMetadata?.oldSessionTimeInterval
        sessionLock.unlock()

        guard let oldSessionId, let oldCreationDate else { return [] }
        return [
            (Keys.sessionId.rawValue, oldSessionId),
            (Keys.sessionCreationDate.rawValue, String(Int(oldCreationDate)))
        ]
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
        // Rotation is purely time-based: if the session is older than 1h, rotate
        // regardless of activity state. Idle state gates *export* (see
        // CoralogixExporter.export), not rotation — the two concerns are
        // independent. The previous `isIdle == false` guard meant an idle session
        // could persist for days and then leak its stale ID onto the next
        // emitted span (24h-session bug).
        //
        // Staleness check AND rotation happen under a single lock acquisition so
        // two concurrent callers can't both see the stale gate and both rotate.
        // Callbacks are captured here and fired AFTER the unlock — see
        // `setupSessionMetadata` for the rationale.
        sessionLock.lock()
        var pending: RotationPendingCallbacks? = nil
        if let creationDate = self.sessionMetadata?.sessionCreationDate,
           self.hasAnHourPassed(since: creationDate) {
            pending = performRotationLocked()
        }
        let result = self.sessionMetadata
        sessionLock.unlock()

        if let pending {
            fireRotationCallbacks(pending)
        }
        return result
    }
    
    public func shutdown() {
        sessionLock.lock()
        self.sessionMetadata = SessionMetadata(sessionId: "",
                                               sessionCreationDate: 0,
                                               using: KeychainManager())
        sessionLock.unlock()
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
    
    /// Captured callback references + the new session id from a rotation that
    /// happened under `sessionLock`. The caller must invoke `fireRotationCallbacks`
    /// AFTER releasing `sessionLock` so callbacks never run while the lock is held.
    private struct RotationPendingCallbacks {
        let endedCallback: (() -> Void)?
        let priorExisted: Bool
        let newSessionId: String?
        let changedCallback: ((String) -> Void)?
        let samplingCallback: ((String) -> Void)?
    }

    /// Performs the session rotation. PRECONDITION: caller must already hold
    /// `sessionLock`. Returns the captured callbacks so the caller can fire them
    /// after releasing the lock. Keeping the gate-check (in the caller) and the
    /// mutation here under the SAME lock acquisition prevents two concurrent
    /// callers from both seeing a stale gate and both rotating.
    private func performRotationLocked() -> RotationPendingCallbacks {
        let priorExisted = (self.sessionMetadata != nil)
        let endedCb = self.sessionEndedCallback

        self.prevSessionMetadata = self.sessionMetadata
        self.sessionMetadata = SessionMetadata(sessionId: UUID().uuidString.lowercased(),
                                               sessionCreationDate: Date().timeIntervalSince1970,
                                               using: KeychainManager())
        // Reset snapshot-throttle so the fresh session can emit its first
        // snapshot immediately. CxRumBuilder.buildSnapshotContextIfNeeded
        // treats nil as "throttle expired", so the next qualifying event
        // (including non-error/non-navigation) fires a snapshot.
        //
        // KNOWN INCONSISTENCY: this write is under sessionLock, but the other
        // accesses to lastSnapshotEventTime in CxRumBuilder.buildSnapshotContextIfNeeded
        // (read at line ~113, write at line ~124) are unsynchronised and run on
        // arbitrary span-emission threads (e.g. URLSession delegates). Optional<Date>
        // is two words on 64-bit, so a torn read concurrent with this reset is
        // theoretically possible — worst case is one skipped or extra snapshot-
        // throttle decision, which is benign for best-effort telemetry. Full
        // synchronisation would require routing CxRumBuilder's accesses through
        // sessionLock-aware accessors; tracked as a follow-up (CX-44589).
        self.lastSnapshotEventTime = nil

        return RotationPendingCallbacks(
            endedCallback: endedCb,
            priorExisted: priorExisted,
            newSessionId: self.sessionMetadata?.sessionId,
            changedCallback: self.sessionChangedCallback,
            samplingCallback: self.samplingReevaluationCallback
        )
    }

    /// Fires the callbacks captured by `performRotationLocked`. PRECONDITION:
    /// caller must NOT hold `sessionLock`. `NSRecursiveLock` protects same-thread
    /// re-entry into `SessionManager`, but does NOT protect against lock-ordering
    /// deadlocks when a callback synchronously hops to another queue/thread
    /// (e.g., a SessionReplay listener) that takes its own lock and then waits on
    /// `sessionLock`. Firing outside the lock removes that vector.
    private func fireRotationCallbacks(_ pending: RotationPendingCallbacks) {
        // The "ended" callback only fires when we're rotating an existing
        // session; the very first setup (from `init`) has no prior session
        // to end.
        if pending.priorExisted {
            pending.endedCallback?()
        }
        if let newId = pending.newSessionId {
            pending.changedCallback?(newId)
            pending.samplingCallback?(newId)
        }
    }

    internal func setupSessionMetadata() {
        sessionLock.lock()
        let pending = performRotationLocked()
        sessionLock.unlock()

        fireRotationCallbacks(pending)
    }

    internal func updateActivityTime() {
        // Both the idle check AND the rotation+gate-close happen under a single
        // lock acquisition. The "gate" that prevents repeat rotation is
        // `lastActivity` — until it's updated, every concurrent caller sees
        // `isIdle == true` and would also rotate. Moving the `lastActivity = Date()`
        // write inside the locked region closes the gate atomically with the
        // rotation decision. A side effect: listeners that consult `isIdle`
        // inside their callback now see `false` (lastActivity already updated)
        // — accepted because preserving the old observation order would re-open
        // the race window.
        sessionLock.lock()
        var pending: RotationPendingCallbacks? = nil
        if isIdle {
            Log.d("[SDK] transitioning from idle to active state")
            pending = performRotationLocked()
        }
        lastActivity = Date()
        sessionLock.unlock()

        if let pending {
            fireRotationCallbacks(pending)
        }
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
