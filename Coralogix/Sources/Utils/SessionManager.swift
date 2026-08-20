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

/// One-shot token representing a pending snapshot promotion requested by
/// `setUserContext`. Its presence *is* the state: `SessionManager` holds at most one,
/// consuming it yields it exactly once, and `CxRum` carries the consumed token so the
/// `beforeSend` drop path can hand it back (re-arm) when the promoted span never ships.
struct PendingSnapshotTrigger {
    /// Session the promotion was requested in. Only spans of this session may carry
    /// the promotion, and a handed-back token re-arms only while this still matches
    /// the active session — a rotation invalidates it, so a delayed `beforeSend` drop
    /// can never promote an event in the fresh session for a prior session's
    /// user-context change.
    let sessionId: String?

    /// The user context captured at arm time. The promoted event's session context is
    /// overridden with this, because neither of its usual sources is guaranteed fresh:
    /// the carrier span's identity attributes were stamped at span creation, and the
    /// exporter options are a struct copied per span at encode — both can predate the
    /// `setUserContext` call that armed this token. nil records a cleared context:
    /// the promoted event reports the empty identity and omits `user_metadata`,
    /// exactly like every non-promoted event after the clear.
    let userContext: UserContext?

    /// When the token was armed. A span that started earlier describes a moment
    /// before the user change — promoting it would rewrite that moment's identity
    /// and contradict what `tracesExporter` already emitted for the same span.
    let armedAt: TimeInterval

    init(sessionId: String? = nil, userContext: UserContext? = nil, armedAt: TimeInterval = 0) {
        self.sessionId = sessionId
        self.userContext = userContext
        self.armedAt = armedAt
    }

    /// Whether a span may carry this promotion: it must belong to the session the
    /// token was armed in and have started at or after the arm. A nil start time is
    /// treated as eligible — losing the promotion over an unstampable span would
    /// drop it for nothing.
    func canPromote(sessionId: String, spanStartTime: TimeInterval?) -> Bool {
        guard self.sessionId == sessionId else { return false }
        guard let spanStartTime else { return true }
        return spanStartTime >= armedAt
    }
}

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
    /// Receives the new session id and **that rotation's own** sampling decision. The decision is
    /// passed rather than re-read: reading `isSessionSampledIn` when the callback runs would pick up
    /// whatever the latest rotation left behind, so a concurrent rotation could make a sampled-in
    /// transition invisible to the callback that was supposed to act on it.
    internal var samplingReevaluationCallback: ((String, Bool) -> Void)?

    /// Rolls the sampling decision for a newly rotated session. Installed once at startup;
    /// invoked inside `performRotationLocked` so the decision is replaced atomically with
    /// the session identity — the single roll per rotation is what both the exporter's
    /// sampling filter and the per-span stamp observe, so they can never disagree.
    internal var samplingRoller: (() -> Bool)?
    private var _isSessionSampledIn: Bool = true

    /// Whether the current session was sampled in. Per-session: re-rolled on every
    /// rotation. Defaults to `true` until the SDK seeds it (sessions created before the
    /// roller is installed inherit the init-time roll via `setSessionSampledIn`).
    internal var isSessionSampledIn: Bool {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return _isSessionSampledIn
    }

    /// Seeds the decision for the session that already exists when the SDK starts up
    /// (created by `init` before `samplingRoller` could be installed).
    internal func setSessionSampledIn(_ sampledIn: Bool) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        _isSessionSampledIn = sampledIn
        persistSessionSampledInLocked(sampledIn)
    }

    /// Mirrors the live decision into the keychain next to the session identity, so a
    /// crash captured on the next launch can be attributed with the crashed session's
    /// decision (`lastLaunchSessionSpanAttributes`) instead of the relaunch's fresh roll.
    /// PRECONDITION: caller holds `sessionLock` (same discipline as the identity writes
    /// in `SessionMetadata.loadPrevSession`, which also run under the lock).
    private func persistSessionSampledInLocked(_ sampledIn: Bool) {
        KeychainManager().writeStringToKeychain(service: Keys.service.rawValue,
                                                key: Keys.keySessionSampledIn.rawValue,
                                                value: String(sampledIn))
    }

    public var hasRecording: Bool = false

    public var lastSnapshotEventTime: Date?

    /// One-shot token armed by `setUserContext` so the next exported event is promoted
    /// to a snapshot event. Mirrors the browser SDK's `shouldTriggerSnapshotContext`:
    /// user data reaches the backend on events, and the backend refreshes session-level
    /// user info from snapshot events — promoting the next event is exactly sufficient,
    /// with no synthetic event type on the wire.
    private var _pendingSnapshotTrigger: PendingSnapshotTrigger?

    func triggerSnapshotOnNextEvent(userContext: UserContext? = nil) {
        // Two-phase like sessionSpanAttributes(): getSessionMetadata() first so a due
        // 1-hour rotation fires now and the token is stamped with the session the next
        // span will actually carry. A direct read would stamp the stale id — no future
        // span could ever match it, and the rotation would then discard the token
        // unconsumed (the 24h-session bug family).
        _ = getSessionMetadata()

        sessionLock.lock()
        defer { sessionLock.unlock() }
        _pendingSnapshotTrigger = PendingSnapshotTrigger(sessionId: sessionMetadata?.sessionId,
                                                         userContext: userContext,
                                                         armedAt: Date().timeIntervalSince1970)
    }

    /// One-shot: yields the token at most once per arm. Take-and-clear is atomic so
    /// concurrent span exports cannot both consume it.
    func consumePendingSnapshotTrigger() -> PendingSnapshotTrigger? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        let pending = _pendingSnapshotTrigger
        _pendingSnapshotTrigger = nil
        return pending
    }

    /// Hands a consumed token back when the promoted span never shipped (`beforeSend`
    /// dropped it, or `build()` rejected an ineligible carrier). The session check runs
    /// under the same lock that rotation holds while clearing the pending token, so a
    /// token from a rotated-out session can never re-arm a promotion in the fresh
    /// session; the rotation check fires first so that comparison is against a live
    /// session, not a stale one. The empty-slot guard keeps a stale hand-back from
    /// displacing a fresher arm: if `setUserContext` ran again while the dropped span
    /// was in flight, the slot already holds the newer context — overwriting it would
    /// promote the previous identity and lose the newer promotion entirely.
    func restorePendingSnapshotTrigger(_ token: PendingSnapshotTrigger) {
        _ = getSessionMetadata()

        sessionLock.lock()
        defer { sessionLock.unlock() }
        guard token.sessionId == sessionMetadata?.sessionId,
              _pendingSnapshotTrigger == nil else { return }
        _pendingSnapshotTrigger = token
    }

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
        let sampledIn = self._isSessionSampledIn
        sessionLock.unlock()

        var attrs: [(key: String, value: String)] = []
        if let current {
            attrs.append((Keys.sessionId.rawValue, current.sessionId))
            attrs.append((Keys.sessionCreationDate.rawValue, String(Int(current.sessionCreationDate))))
            attrs.append((Keys.spanSessionSampledIn.rawValue, String(sampledIn)))
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
        let oldSampledIn = self.sessionMetadata?.oldSessionSampledIn
        sessionLock.unlock()

        guard let oldSessionId, let oldCreationDate else { return [] }
        // nil (prior launch predates the persisted decision) defaults to true: a
        // recovered crash misclassified as sampled-out could be dropped by a
        // customer's beforeSend filter — the failure mode this feature exists to avoid.
        return [
            (Keys.sessionId.rawValue, oldSessionId),
            (Keys.sessionCreationDate.rawValue, String(Int(oldCreationDate))),
            (Keys.spanSessionSampledIn.rawValue, String(oldSampledIn ?? true))
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
        // Symmetric with rotation: with the session id blanked the token could never
        // be consumed again, so it would otherwise outlive the teardown still holding
        // the user's identity.
        self._pendingSnapshotTrigger = nil
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
        let samplingCallback: ((String, Bool) -> Void)?
        /// Captured under the same lock acquisition as the roll, so it is the decision belonging to
        /// this rotation and not whatever a later one may already have replaced it with.
        let sampledIn: Bool
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
        // Roll the new session's sampling decision under the same lock acquisition that
        // replaces the session identity, so no span can observe a fresh session_id with
        // the previous session's sampling decision (or vice versa). Absent roller (before
        // startup installs it) keeps the seeded/default value.
        if let samplingRoller = self.samplingRoller {
            self._isSessionSampledIn = samplingRoller()
            persistSessionSampledInLocked(self._isSessionSampledIn)
        }
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
        // A pending user-context snapshot must not leak into the fresh session — the
        // nil throttle above already guarantees the new session's first qualifying
        // event emits a snapshot carrying the current user context.
        self._pendingSnapshotTrigger = nil

        return RotationPendingCallbacks(
            endedCallback: endedCb,
            priorExisted: priorExisted,
            newSessionId: self.sessionMetadata?.sessionId,
            changedCallback: self.sessionChangedCallback,
            samplingCallback: self.samplingReevaluationCallback,
            sampledIn: self._isSessionSampledIn
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
            pending.samplingCallback?(newId, pending.sampledIn)
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
