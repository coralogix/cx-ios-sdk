//
//  RumBusTests.swift
//
//  The RUM bus: the two-way, fire-and-forget channel the session-replay wrapper subscribes to.
//  RUM publishes its side here (sticky CurrentState, SessionChanged, ViewChanged, ShuttingDown,
//  Flushing); replay's side (`publish`) is accepted and, with no RUM handler installed, dropped.
//
//  SANCTIONED SYMBOLS (the implementation may create exactly these; tests use nothing else new):
//
//  In module `Coralogix`, each declared `@_spi(RumBus) public` (never plain `public`), cases,
//  labels and shapes exactly as below:
//    enum RumBusScalar: Sendable, Equatable { case string(String), number(Double), bool(Bool), null }
//    enum RumToReplay: Sendable, Equatable {
//        case currentState(sessionId: String, sessionStartTime: Int, kept: Bool, idle: Bool,
//                          currentScreen: String?, maskTag: String)
//        case sessionChanged(sessionId: String, sessionStartTime: Int, kept: Bool, idle: Bool)
//        case viewChanged(screen: String)
//        case shuttingDown
//        case flushing }
//    enum ReplayToRum: Sendable, Equatable {
//        case recordingStarted(sessionId: String)
//        case recordingStopped(sessionId: String)
//        case screenshotTaken(screenshotId: String, sessionId: String, timestamp: Int)
//        case replaySettings(settings: [String: RumBusScalar]) }
//    final class RumBusSubscription { func cancel() }   — nothing queued after cancel() is delivered
//    final class RumBus                                  — one per process, outlives init/shutdown/re-init
//    static func CoralogixRum.subscribe(_ handler: @escaping @Sendable (RumToReplay) -> Void) -> RumBusSubscription
//    static func CoralogixRum.publish(_ message: ReplayToRum)   — enqueues and returns
//
//  Internal (not SPI, not public):
//    RumBus.rumPublish(_:), RumBus.setRumHandler(_:), RumBus.drain()
//    static func CoralogixRum.drainBus()
//        Test seam: returns once every delivery queued on the bus before the call has run.
//    var SessionManager.scheduleIdleCheck: (_ delay: TimeInterval, _ check: @escaping () -> Void) -> Void
//        Test seam for the timed idle onset. Called every time the idle check is armed, with
//        delay = (lastActivity + idle timeout) - now, in seconds; `check` runs the check. Armed on
//        every rotation, on every activity (`updateActivityTime`) and when a check runs before the
//        session is idle (strict `>`, as `isIdle`). Default: a real one-shot timer that fires after
//        `delay` on its own, without activity (main or background queue).
//
//  `CurrentState.maskTag` is the constant "cxMask". `sessionStartTime` is epoch milliseconds.
//  `kept` is the session's sampling decision (`SessionManager.isSessionSampledIn`).
//  The live instance is the most recently initialized one; any other instance publishes nothing, and
//  nothing is published while RUM is not initialized. Flushing comes only from the app's own `flush()`;
//  RUM's internal flushes (background, crash report) go through a path that does not publish.
//
//  Every test is marked RED-now (fails until the bus is implemented) or GUARD (states a property the
//  implementation must not break). With no bus types in the module the whole file fails to compile:
//  that is the RED state.
//

import XCTest
import CrashReporter
#if canImport(UIKit)
import UIKit
#endif
@_spi(RumBus) @testable import Coralogix

final class RumBusTests: XCTestCase {

    private var subscriptions: [RumBusSubscription] = []

    override func setUp() {
        super.setUp()
        CoralogixRum.isInitialized = false
        // The bus is process-wide: an instance another test left running would leave its sticky
        // state behind. One init + shutdown leaves the bus with no sticky state.
        CoralogixRum(options: Self.options()).shutdown()
        CoralogixRum.drainBus()
    }

    override func tearDown() {
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        CoralogixRum.isInitialized = false
        super.tearDown()
    }

    // MARK: - CurrentState (sticky, first)

    /// RED-now. A subscriber after init gets the live session's CurrentState first.
    func testSubscribeAfterInit_firstMessageIsCurrentStateOfTheLiveSession() {
        let sm = Self.sessionManager()
        let rum = CoralogixRum(options: Self.options(), sessionManager: sm)
        defer { rum.shutdown() }

        let rec = subscribe()
        CoralogixRum.drainBus()

        XCTAssertEqual(rec.messages.count, 1, "exactly the sticky CurrentState: \(rec.messages)")
        guard case let .currentState(id, start, kept, idle, screen, maskTag)? = rec.messages.first else {
            return XCTFail("first message must be CurrentState, got \(rec.messages)")
        }
        XCTAssertEqual(id, sm.currentSessionId)
        XCTAssertFalse(id.isEmpty)
        Self.assertStartTime(start, of: sm)
        XCTAssertTrue(kept, "sample rate 100: the session is kept")
        XCTAssertFalse(idle)
        XCTAssertNil(screen, "no view was set yet")
        XCTAssertEqual(maskTag, "cxMask")
    }

    /// RED-now. CurrentState carries the same url-masked name ViewChanged does.
    func testSubscribeAfterSetView_currentStateCarriesTheMaskedScreen() {
        let rum = CoralogixRum(options: Self.options())
        defer { rum.shutdown() }
        let raw = "Reset?token=abc"
        let masked = Self.masked(raw)
        XCTAssertNotEqual(masked, raw, "fixture must actually mask")

        rum.setView(name: raw)
        let rec = subscribe()
        CoralogixRum.drainBus()

        guard case let .currentState(_, _, _, _, screen, _)? = rec.messages.first else {
            return XCTFail("first message must be CurrentState, got \(rec.messages)")
        }
        XCTAssertEqual(screen, masked)
    }

    /// RED-now. Replay can subscribe before RUM starts.
    func testSubscribeBeforeInit_getsNothingUntilInit_thenCurrentStateFirst() {
        let rec = subscribe()
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages, [], "RUM is not initialized: nothing to deliver")

        let sm = Self.sessionManager()
        let rum = CoralogixRum(options: Self.options(), sessionManager: sm)
        defer { rum.shutdown() }
        CoralogixRum.drainBus()

        XCTAssertEqual(rec.messages.count, 1, "init delivers CurrentState only: \(rec.messages)")
        guard case let .currentState(id, _, _, _, _, maskTag)? = rec.messages.first else {
            return XCTFail("first message after init must be CurrentState, got \(rec.messages)")
        }
        XCTAssertEqual(id, sm.currentSessionId)
        XCTAssertEqual(maskTag, "cxMask")
    }

    /// RED-now. Nothing reaches a subscriber while RUM is shut down; the same subscriber gets CurrentState on re-init.
    func testSubscribeAfterShutdown_getsNothing() {
        let rum = CoralogixRum(options: Self.options())
        rum.shutdown()

        let rec = subscribe()
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages, [], "shutdown clears the sticky state")

        // Non-vacuous: the same subscriber gets CurrentState once RUM is back.
        let rum2 = CoralogixRum(options: Self.options())
        defer { rum2.shutdown() }
        CoralogixRum.drainBus()
        guard case .currentState? = rec.messages.first else {
            return XCTFail("after re-init the subscriber must get CurrentState, got \(rec.messages)")
        }
    }

    /// RED-now. A late subscriber's CurrentState carries the session as it stands now: the rotated id and
    /// start time, then a sampled-out session gone idle.
    func testLateSubscriber_currentStateFollowsRotationSamplingAndIdle() {
        let (rum, sm, arms) = Self.rumWithIdleArms()
        defer { rum.shutdown() }
        let firstId = sm.currentSessionId

        rum.createNewSession()
        XCTAssertNotEqual(sm.currentSessionId, firstId, "fixture: rotated")
        let late1 = subscribe()
        CoralogixRum.drainBus()
        XCTAssertEqual(late1.messages.count, 1, "\(late1.messages)")
        guard case let .currentState(id1, start1, kept1, idle1, _, _)? = late1.messages.first else {
            return XCTFail("expected CurrentState, got \(late1.messages)")
        }
        XCTAssertEqual(id1, sm.currentSessionId)
        Self.assertStartTime(start1, of: sm)
        XCTAssertTrue(kept1)
        XCTAssertFalse(idle1)

        sm.samplingRoller = { false }
        rum.createNewSession()
        sm.lastActivity = Date().addingTimeInterval(-(16 * 60))
        arms.last?.check()
        let late2 = subscribe()
        CoralogixRum.drainBus()
        XCTAssertEqual(late2.messages.count, 1, "\(late2.messages)")
        guard case let .currentState(id2, start2, kept2, idle2, _, _)? = late2.messages.first else {
            return XCTFail("expected CurrentState, got \(late2.messages)")
        }
        XCTAssertEqual(id2, sm.currentSessionId)
        XCTAssertNotEqual(id2, id1)
        Self.assertStartTime(start2, of: sm)
        XCTAssertFalse(kept2, "the sampled-out session")
        XCTAssertTrue(idle2, "the idle onset")
    }

    /// RED-now. Subscribing never rotates the session, even one past max age.
    func testSubscribe_neverRotatesTheSession() {
        let sm = Self.sessionManager()
        let rum = CoralogixRum(options: Self.options(), sessionManager: sm)
        defer { rum.shutdown() }
        Self.expire(sm)
        let id = sm.currentSessionId

        let rec = subscribe()
        CoralogixRum.drainBus()

        XCTAssertEqual(sm.currentSessionId, id, "subscribing must not rotate")
        XCTAssertEqual(rec.messages.count, 1, "exactly one CurrentState: \(rec.messages)")
        guard case let .currentState(sid, _, _, _, _, _)? = rec.messages.first else {
            return XCTFail("expected CurrentState, got \(rec.messages)")
        }
        XCTAssertEqual(sid, id)
    }

    // MARK: - SessionChanged

    /// RED-now. A session reset publishes one SessionChanged.
    func testCreateNewSession_publishesOneSessionChangedForTheNewSession() {
        let sm = Self.sessionManager()
        let rum = CoralogixRum(options: Self.options(), sessionManager: sm)
        defer { rum.shutdown() }
        let rec = subscribeAndSkipCurrentState()
        let oldId = sm.currentSessionId

        rum.createNewSession()
        CoralogixRum.drainBus()

        XCTAssertEqual(rec.messages.count, 1, "one rotation, one SessionChanged: \(rec.messages)")
        Self.assertSessionChanged(rec.messages.first, sm: sm, kept: true, idle: false)
        XCTAssertNotEqual(sm.currentSessionId, oldId)
    }

    /// RED-now. RUM's own max-age rotation publishes.
    func testMaxAgeExpiry_publishesSessionChangedWhenRumRotates() {
        let sm = Self.sessionManager()
        let rum = CoralogixRum(options: Self.options(), sessionManager: sm)
        defer { rum.shutdown() }
        let rec = subscribeAndSkipCurrentState()
        let oldId = sm.currentSessionId
        Self.expire(sm)

        _ = sm.getSessionMetadata() // RUM's rotating read
        CoralogixRum.drainBus()

        XCTAssertNotEqual(sm.currentSessionId, oldId, "fixture: the expired session rotated")
        XCTAssertEqual(rec.messages.count, 1, "\(rec.messages)")
        Self.assertSessionChanged(rec.messages.first, sm: sm, kept: true, idle: false)
    }

    /// RED-now. Sampled-out sessions publish too, with kept = the session's roll.
    func testSampling_keptFollowsEachSessionsRoll() {
        let sm = Self.sessionManager()
        let rum = CoralogixRum(options: Self.options(sampleRate: 0), sessionManager: sm)
        defer { rum.shutdown() }
        let rec = subscribe()
        CoralogixRum.drainBus()
        guard case let .currentState(_, _, kept, _, _, _)? = rec.messages.first else {
            return XCTFail("first message must be CurrentState, got \(rec.messages)")
        }
        XCTAssertFalse(kept, "sample rate 0: the first session is sampled out")
        XCTAssertFalse(sm.isSessionSampledIn)
        rec.clear()

        sm.samplingRoller = { true }
        rum.createNewSession()
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages.count, 1, "\(rec.messages)")
        Self.assertSessionChanged(rec.messages.first, sm: sm, kept: true, idle: false)
        rec.clear()

        sm.samplingRoller = { false }
        rum.createNewSession()
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages.count, 1, "a sampled-out rotation still publishes: \(rec.messages)")
        Self.assertSessionChanged(rec.messages.first, sm: sm, kept: false, idle: false)
    }

    /// RED-now. Idle is lazy in RUM, so a timed check
    /// publishes `idle: true` with no further activity, same session id.
    func testIdleOnsetByTimer_publishesIdleTrueWithoutFurtherActivity() {
        let (rum, sm, arms) = Self.rumWithIdleArms()
        defer { rum.shutdown() }
        let rec = subscribeAndSkipCurrentState()
        let id = sm.currentSessionId

        sm.lastActivity = Date().addingTimeInterval(-(16 * 60))
        guard let check = arms.last?.check else { return XCTFail("activity must arm the idle check") }
        check()
        CoralogixRum.drainBus()

        XCTAssertEqual(sm.currentSessionId, id, "idle onset does not rotate")
        XCTAssertEqual(rec.messages.count, 1, "\(rec.messages)")
        Self.assertSessionChanged(rec.messages.first, sm: sm, kept: true, idle: true)
    }

    /// RED-now. The idle check is armed at lastActivity + timeout, re-armed on activity and on every rotation.
    func testIdleCheck_isArmedAtLastActivityPlusTimeout_onActivityAndOnRotation() {
        let (rum, sm, arms) = Self.rumWithIdleArms()
        defer { rum.shutdown() }
        XCTAssertEqual(arms.count, 1, "activity arms one check")
        XCTAssertEqual(arms.last?.delay ?? -1, 15 * 60, accuracy: 2)

        sm.lastActivity = Date().addingTimeInterval(-100)
        rum.createNewSession()
        XCTAssertEqual(arms.count, 2, "a rotation re-arms the check")
        XCTAssertEqual(arms.last?.delay ?? -1, 15 * 60 - 100, accuracy: 2,
                       "armed at lastActivity + timeout, not at now + timeout")

        sm.updateActivityTime()
        XCTAssertEqual(arms.count, 3, "activity re-arms the check")
        XCTAssertEqual(arms.last?.delay ?? -1, 15 * 60, accuracy: 2)
    }

    /// RED-now (the re-arm half). A check that runs before the session is idle publishes nothing and re-arms.
    func testIdleCheckRunningEarly_publishesNothing_andReArms() {
        let (rum, sm, arms) = Self.rumWithIdleArms()
        defer { rum.shutdown() }
        let rec = subscribeAndSkipCurrentState()
        sm.lastActivity = Date().addingTimeInterval(-60)
        let before = arms.count

        arms.last?.check()
        CoralogixRum.drainBus()

        XCTAssertEqual(rec.messages, [], "not idle yet: nothing changed")
        XCTAssertEqual(arms.count, before + 1, "an early check re-arms")
        XCTAssertEqual(arms.last?.delay ?? -1, 15 * 60 - 60, accuracy: 2)
    }

    /// RED-now. Activity after idle starts a new session — one SessionChanged, idle false.
    func testResumeAfterIdle_publishesOneSessionChangedForTheNewSession() {
        let (rum, sm, arms) = Self.rumWithIdleArms()
        defer { rum.shutdown() }
        let rec = subscribeAndSkipCurrentState()
        let idleId = sm.currentSessionId
        sm.lastActivity = Date().addingTimeInterval(-(16 * 60))
        arms.last?.check()
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages.count, 1, "idle onset published first: \(rec.messages)")
        rec.clear()

        sm.updateActivityTime()
        CoralogixRum.drainBus()

        XCTAssertNotEqual(sm.currentSessionId, idleId, "fixture: resume rotated")
        XCTAssertEqual(rec.messages.count, 1, "\(rec.messages)")
        Self.assertSessionChanged(rec.messages.first, sm: sm, kept: true, idle: false)
    }

    /// RED-now. Bus reads never rotate: an idle check on a session past max age reports that
    /// session going idle; it does not rotate it.
    func testIdleCheckOnAnExpiredSession_doesNotRotate() {
        let (rum, sm, arms) = Self.rumWithIdleArms()
        defer { rum.shutdown() }
        let rec = subscribeAndSkipCurrentState()
        let id = sm.currentSessionId
        Self.expire(sm)
        sm.lastActivity = Date().addingTimeInterval(-(16 * 60))

        arms.last?.check()
        CoralogixRum.drainBus()

        XCTAssertEqual(sm.currentSessionId, id, "the idle check must not rotate the session")
        XCTAssertEqual(rec.messages.count, 1, "\(rec.messages)")
        guard case let .sessionChanged(sid, _, _, idle)? = rec.messages.first else {
            return XCTFail("expected SessionChanged, got \(rec.messages)")
        }
        XCTAssertEqual(sid, id)
        XCTAssertTrue(idle)
    }

    /// RED-now. The default `scheduleIdleCheck` really fires: with the idle timeout 0.2 s away, a rotation
    /// re-arms the real check and `idle: true` arrives with no further activity. The expectation wait spins
    /// the main run loop, so a default timer on the main queue or on a background queue both fire.
    func testDefaultIdleTimer_publishesIdleOnsetOnItsOwn() {
        let sm = Self.sessionManager()
        let rum = CoralogixRum(options: Self.options(), sessionManager: sm)
        defer { rum.shutdown() }
        let wentIdle = expectation(description: "SessionChanged idle: true")
        wentIdle.assertForOverFulfill = false
        let rec = Recorder()
        subscriptions.append(CoralogixRum.subscribe { message in
            rec.record(message)
            if case .sessionChanged(_, _, _, true) = message { wentIdle.fulfill() }
        })

        sm.lastActivity = Date().addingTimeInterval(-(15 * 60 - 0.2))
        rum.createNewSession() // re-arms the real check ~0.2 s ahead
        let id = sm.currentSessionId
        wait(for: [wentIdle], timeout: 5)

        guard case let .sessionChanged(sid, _, _, idle)? = rec.messages.last else {
            return XCTFail("expected SessionChanged, got \(rec.messages)")
        }
        XCTAssertEqual(sid, id, "idle onset keeps the session")
        XCTAssertTrue(idle)
    }

    /// RED-now. No SessionChanged (and no duplicate) when nothing changed.
    func testNothingChanged_publishesNothing() {
        let (rum, sm, arms) = Self.rumWithIdleArms()
        defer { rum.shutdown() }
        let rec = subscribeAndSkipCurrentState()

        sm.updateActivityTime() // active → active
        _ = rum.getSessionId
        _ = sm.getSessionMetadata()
        rum.setView(name: "Same")
        rum.setView(name: "Same")
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages, [.viewChanged(screen: "Same")], "only the first setView changed anything")
        rec.clear()

        sm.lastActivity = Date().addingTimeInterval(-(16 * 60))
        let check = arms.last?.check
        check?()
        check?()
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages.count, 1, "idle onset is published once: \(rec.messages)")
    }

    /// RED-now (the non-vacuous half: the live manager does publish). Only the live session manager publishes.
    func testShutDownSessionManager_staysSilent() {
        let (rum, sm, arms) = Self.rumWithIdleArms()
        let rec = subscribe()
        rum.shutdown()
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages.last, .shuttingDown, "fixture: \(rec.messages)")
        rec.clear()

        sm.setupSessionMetadata()             // rotation on the shut-down manager
        sm.lastActivity = Date().addingTimeInterval(-(16 * 60))
        arms.last?.check()                    // its timed idle check
        sm.updateActivityTime()               // its resume
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages, [], "a shut-down manager publishes nothing")

        let sm2 = Self.sessionManager()
        let rum2 = CoralogixRum(options: Self.options(), sessionManager: sm2)
        defer { rum2.shutdown() }
        CoralogixRum.drainBus()
        rec.clear()
        sm.setupSessionMetadata()
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages, [], "the old manager stays silent while a new instance is live")

        rum2.createNewSession()
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages.count, 1, "the live manager publishes: \(rec.messages)")
        Self.assertSessionChanged(rec.messages.first, sm: sm2, kept: true, idle: false)
    }

    /// RED-now (the non-vacuous half: the newest instance does publish). The live instance is
    /// the most recently initialized one; an older instance that was never shut down publishes nothing.
    /// This is also what isolates these tests from instances other test classes leave running: `setUp`'s
    /// init makes every such leftover older than the instance each test creates.
    func testOlderNeverShutDownInstance_staysSilent() {
        let sm1 = Self.sessionManager()
        let rum1 = CoralogixRum(options: Self.options(), sessionManager: sm1)
        let sm2 = Self.sessionManager()
        let rum2 = CoralogixRum(options: Self.options(), sessionManager: sm2)
        let rec = subscribeAndSkipCurrentState()
        defer {
            subscriptions.forEach { $0.cancel() }
            rum2.shutdown()
            rum1.shutdown()
        }

        sm1.setupSessionMetadata()   // rotation on the older manager
        rum1.createNewSession()
        rum1.setView(name: "Old")
        rum1.flush()
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages, [], "the older instance publishes nothing")

        // Both instances observe the navigation notification; only the newest one publishes.
        NotificationCenter.default.post(name: .cxRumNotification, object: CXView(state: .notifyOnAppear, name: "Shared"))
        rum2.createNewSession()
        CoralogixRum.drainBus()
        guard rec.messages.count == 2 else { return XCTFail("one ViewChanged, one SessionChanged: \(rec.messages)") }
        XCTAssertEqual(rec.messages[0], .viewChanged(screen: "Shared"))
        Self.assertSessionChanged(rec.messages[1], sm: sm2, kept: true, idle: false)
    }

    /// RED-now. A newer init while an older instance still runs gives an existing subscriber exactly one
    /// SessionChanged for the new instance's session, and no ShuttingDown.
    func testNewerInitOverARunningInstance_givesExistingSubscriberOneSessionChanged() {
        let rum1 = CoralogixRum(options: Self.options())
        let rec = subscribeAndSkipCurrentState()
        let sm2 = Self.sessionManager()
        let rum2 = CoralogixRum(options: Self.options(), sessionManager: sm2)
        defer {
            subscriptions.forEach { $0.cancel() }
            rum2.shutdown()
            rum1.shutdown()
        }
        CoralogixRum.drainBus()

        XCTAssertEqual(rec.messages.count, 1, "\(rec.messages)")
        Self.assertSessionChanged(rec.messages.first, sm: sm2, kept: true, idle: false)
    }

    /// RED-now (fixture half: ShuttingDown) + GUARD (nothing after it). Nothing is published while RUM is not initialized.
    func testNothingPublishedWhileNotInitialized() {
        let rec = subscribe() // setUp left RUM shut down
        let rum = CoralogixRum(options: Self.options())
        rum.shutdown()
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages.last, .shuttingDown, "fixture: \(rec.messages)")
        rec.clear()

        rum.flush()
        rum.setView(name: "AfterShutdown")
        NotificationCenter.default.post(name: .cxRumNotification,
                                        object: CXView(state: .notifyOnAppear, name: "AfterShutdownNav"))
        rum.createNewSession()
        CoralogixRum.drainBus()

        XCTAssertEqual(rec.messages, [], "no Flushing, ViewChanged or SessionChanged while RUM is down")
    }

    // MARK: - ViewChanged

    /// RED-now. Masked name on the wire, dedup on the raw name, empty name ignored.
    func testSetView_publishesMaskedName_dedupsOnRawName_ignoresEmpty() {
        let rum = CoralogixRum(options: Self.options())
        defer { rum.shutdown() }
        let rec = subscribeAndSkipCurrentState()
        let rawA = "Reset?token=abc", rawB = "Reset?token=xyz"
        let masked = Self.masked(rawA)
        XCTAssertNotEqual(masked, rawA, "fixture must actually mask")
        XCTAssertEqual(Self.masked(rawB), masked, "fixture: the two raw names mask alike")

        rum.setView(name: rawA)
        rum.setView(name: rawA)   // same raw name: no change
        rum.setView(name: rawB)   // different raw name, same masked name: a change
        rum.setView(name: "")     // ignored
        CoralogixRum.drainBus()

        XCTAssertEqual(rec.messages, [.viewChanged(screen: masked), .viewChanged(screen: masked)])

        let late = subscribe()
        CoralogixRum.drainBus()
        guard case let .currentState(_, _, _, _, screen, _)? = late.messages.first else {
            return XCTFail("expected CurrentState, got \(late.messages)")
        }
        XCTAssertEqual(screen, masked, "the empty name left the sticky screen unchanged")
    }

    /// RED-now. Automatic navigation (the screen notification UIKit/SwiftUI post) publishes too.
    func testNavigationNotification_publishesMaskedViewChanged() {
        let rum = CoralogixRum(options: Self.options())
        defer { rum.shutdown() }
        let rec = subscribeAndSkipCurrentState()
        let raw = "Nav?token=abc"

        NotificationCenter.default.post(name: .cxRumNotification,
                                        object: CXView(state: .notifyOnAppear, name: raw))
        CoralogixRum.drainBus()

        XCTAssertEqual(rec.messages, [.viewChanged(screen: Self.masked(raw))])
    }

    // MARK: - ShuttingDown, Flushing

    /// RED-now. ShuttingDown once, nothing from the teardown, sticky cleared.
    func testShutdown_publishesShuttingDownOnce_andClearsTheStickyState() {
        let rum = CoralogixRum(options: Self.options())
        let rec = subscribeAndSkipCurrentState()

        rum.shutdown()
        rum.shutdown()
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages, [.shuttingDown], "one ShuttingDown and nothing else (no blanked-session SessionChanged)")

        let late = subscribe()
        CoralogixRum.drainBus()
        XCTAssertEqual(late.messages, [])
    }

    /// RED-now. Only the app's own flush() publishes Flushing; RUM's internal flushes (background, crash report) do not.
    func testFlushing_onAppFlushOnly() {
        let rum = CoralogixRum(options: Self.options())
        defer { rum.shutdown() }
        let rec = subscribeAndSkipCurrentState()

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages, [], "the background flush is RUM's own, not the app's")

        // A hybrid crash report flushes the batch queue internally.
        rum.reportError(message: "boom", stackTrace: [], errorType: "Fatal", isCrash: true)
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages, [], "the crash-report flush is RUM's own, not the app's")

        rum.flush()
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages, [.flushing])
    }

    // MARK: - Delivery

    /// RED-now. One queue, publish order.
    func testMessagesArriveInPublishOrder() {
        let sm = Self.sessionManager()
        let rum = CoralogixRum(options: Self.options(), sessionManager: sm)
        defer { rum.shutdown() }
        let rec = subscribeAndSkipCurrentState()

        rum.setView(name: "A")
        rum.setView(name: "B")
        rum.setView(name: "C")
        rum.createNewSession()
        rum.flush()
        CoralogixRum.drainBus()

        guard rec.messages.count == 5 else { return XCTFail("expected 5 messages, got \(rec.messages)") }
        XCTAssertEqual(Array(rec.messages[0..<3]),
                       [.viewChanged(screen: "A"), .viewChanged(screen: "B"), .viewChanged(screen: "C")])
        Self.assertSessionChanged(rec.messages[3], sm: sm, kept: true, idle: false)
        XCTAssertEqual(rec.messages[4], .flushing)
    }

    /// RED-now. A blocked handler does not block RUM's caller (fire-and-forget).
    func testBlockedHandler_doesNotBlockRumsCaller() {
        let rum = CoralogixRum(options: Self.options())
        defer { rum.shutdown() }
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let callerWasBlocked = Flag()
        subscriptions.append(CoralogixRum.subscribe { message in
            guard message == .viewChanged(screen: "Blocking") else { return }
            entered.signal()
            // Times out only if RUM's caller is stuck waiting for this handler.
            if release.wait(timeout: .now() + 5) == .timedOut { callerWasBlocked.set() }
        })

        rum.setView(name: "Blocking")
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success, "the handler must run on the bus queue")
        rum.setView(name: "Next")
        rum.createNewSession()
        rum.flush()
        release.signal()
        CoralogixRum.drainBus()

        XCTAssertFalse(callerWasBlocked.value, "RUM waited on a subscriber's handler")
    }

    /// RED-now. A handler that re-enters the bus and reads RUM's session does not deadlock.
    func testReentrantHandler_doesNotDeadlock() {
        let sm = Self.sessionManager()
        let rum = CoralogixRum(options: Self.options(), sessionManager: sm)
        defer { rum.shutdown() }
        let done = DispatchSemaphore(value: 0)
        let inner = Recorder()
        subscriptions.append(CoralogixRum.subscribe { message in
            guard message == .viewChanged(screen: "Reenter") else { return }
            let sub = CoralogixRum.subscribe { inner.record($0) }
            CoralogixRum.publish(.recordingStarted(sessionId: sm.currentSessionId ?? ""))
            _ = sm.getSessionMetadata()
            _ = sm.isSessionSampledIn
            sub.cancel()
            done.signal()
        })

        rum.setView(name: "Reenter")
        XCTAssertEqual(done.wait(timeout: .now() + 5), .success, "the re-entrant handler never finished")
        drainWithTimeout()
    }

    /// RED-now. Lock order (session → bus): handlers reading the session lock while RUM rotates do not deadlock.
    func testHandlersReadingTheSessionWhileRumRotates_doNotDeadlock() {
        let sm = Self.sessionManager()
        let rum = CoralogixRum(options: Self.options(), sessionManager: sm)
        defer { rum.shutdown() }
        let seen = Recorder()
        subscriptions.append(CoralogixRum.subscribe { message in
            _ = sm.currentSessionId
            _ = sm.isSessionSampledIn
            seen.record(message)
        })

        let rotations = 50
        let finished = expectation(description: "rotations finished")
        DispatchQueue.global().async {
            for _ in 0..<rotations { rum.createNewSession() }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 10)
        drainWithTimeout()

        XCTAssertEqual(seen.messages.filter { if case .sessionChanged = $0 { return true }; return false }.count,
                       rotations, "every rotation delivered once")
    }

    /// RED-now. cancel() stops delivery of anything queued after it.
    func testCancel_stopsDeliveryOfLaterMessages() {
        let rum = CoralogixRum(options: Self.options())
        defer { rum.shutdown() }
        let rec = Recorder()
        let sub = CoralogixRum.subscribe { rec.record($0) }
        CoralogixRum.drainBus()
        XCTAssertEqual(rec.messages.count, 1, "fixture: the subscription was live (CurrentState)")

        sub.cancel()
        rum.setView(name: "After")
        rum.createNewSession()
        rum.flush()
        CoralogixRum.drainBus()

        XCTAssertEqual(rec.messages.count, 1, "nothing after cancel(): \(rec.messages)")
    }

    /// RED-now. An existing subscriber gets SessionChanged on re-init, a new one gets CurrentState.
    func testReinitAfterShutdown_existingSubscriberGetsSessionChanged() {
        let rec = subscribe()
        let sm1 = Self.sessionManager()
        let rum1 = CoralogixRum(options: Self.options(), sessionManager: sm1)
        rum1.shutdown()
        let sm2 = Self.sessionManager()
        let rum2 = CoralogixRum(options: Self.options(), sessionManager: sm2)
        defer { rum2.shutdown() }
        CoralogixRum.drainBus()

        guard rec.messages.count == 3 else { return XCTFail("expected CurrentState, ShuttingDown, SessionChanged: \(rec.messages)") }
        guard case .currentState? = rec.messages.first else { return XCTFail("\(rec.messages)") }
        XCTAssertEqual(rec.messages[1], .shuttingDown)
        Self.assertSessionChanged(rec.messages[2], sm: sm2, kept: true, idle: false)

        let late = subscribe()
        CoralogixRum.drainBus()
        guard case let .currentState(id, _, _, _, _, _)? = late.messages.first else {
            return XCTFail("a new subscriber gets CurrentState: \(late.messages)")
        }
        XCTAssertEqual(id, sm2.currentSessionId)
    }

    /// GUARD (RED-now by compile only). Replay → RUM with no RUM handler is dropped.
    func testPublishWithNoRumHandler_isDroppedWithoutCrashing() {
        let messages: [ReplayToRum] = [
            .recordingStarted(sessionId: "s"),
            .recordingStopped(sessionId: "s"),
            .screenshotTaken(screenshotId: "shot", sessionId: "s", timestamp: 1),
            .replaySettings(settings: ["a": .string("x"), "b": .number(1), "c": .bool(true), "d": .null])
        ]
        messages.forEach(CoralogixRum.publish) // before init

        let rum = CoralogixRum(options: Self.options())
        defer { rum.shutdown() }
        let rec = subscribeAndSkipCurrentState()
        messages.forEach(CoralogixRum.publish) // after init, no handler installed
        CoralogixRum.drainBus()

        XCTAssertEqual(rec.messages, [], "replay's messages are never echoed to subscribers")
    }

    // MARK: - Real rotation on the simulator

    /// RED-now. A subscriber records a real session rotation driven through RUM's own
    /// SessionManager (the launch manager, the tap notification RUM observes).
    func testRealSessionRotation_fromATapAfterIdle_isRecordedBySubscriber() {
        let rum = CoralogixRum(options: Self.options())
        defer { rum.shutdown() }
        guard let sm = rum.sessionManager else { return XCTFail("RUM has a session manager") }
        let rec = subscribeAndSkipCurrentState()
        let oldId = sm.currentSessionId

        sm.lastActivity = Date().addingTimeInterval(-(16 * 60))
        NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: nil)
        CoralogixRum.drainBus()

        let newId = sm.currentSessionId
        XCTAssertNotEqual(newId, oldId, "fixture: the tap after idle rotated the session")
        // The idle check never fired, so resume publishes only the new session (no idle: true first).
        XCTAssertEqual(rec.messages.count, 1, "\(rec.messages)")
        guard case let .sessionChanged(id, _, kept, idle)? = rec.messages.last else {
            return XCTFail("expected a SessionChanged, got \(rec.messages)")
        }
        XCTAssertEqual(id, newId)
        XCTAssertTrue(kept)
        XCTAssertFalse(idle)
    }

    // MARK: - Helpers

    private func subscribe() -> Recorder {
        let rec = Recorder()
        subscriptions.append(CoralogixRum.subscribe { rec.record($0) })
        return rec
    }

    /// Subscribes after init, checks the sticky CurrentState arrived, and clears it.
    private func subscribeAndSkipCurrentState(file: StaticString = #filePath, line: UInt = #line) -> Recorder {
        let rec = subscribe()
        CoralogixRum.drainBus()
        if case .currentState? = rec.messages.first {} else {
            XCTFail("expected the sticky CurrentState first, got \(rec.messages)", file: file, line: line)
        }
        rec.clear()
        return rec
    }

    private func drainWithTimeout(file: StaticString = #filePath, line: UInt = #line) {
        let drained = expectation(description: "bus drained")
        DispatchQueue.global().async {
            CoralogixRum.drainBus()
            drained.fulfill()
        }
        wait(for: [drained], timeout: 10) // a deadlocked bus queue never drains
    }

    private static func options(sampleRate: Int = 100) -> CoralogixExporterOptions {
        CoralogixExporterOptions(coralogixDomain: .US2,
                                 userContext: nil,
                                 environment: "test",
                                 application: "TestApp",
                                 version: "1.0.0",
                                 publicKey: "test-key",
                                 ignoreUrls: [],
                                 ignoreErrors: [],
                                 labels: nil,
                                 sessionSampleRate: sampleRate,
                                 excludeFromSampling: [],
                                 instrumentations: nil,
                                 debug: false)
    }

    private static func sessionManager() -> SessionManager {
        SessionManager(snapshotStore: SessionSnapshotStore())
    }

    /// A RUM whose session manager hands its idle checks to the test; one check armed by activity.
    private static func rumWithIdleArms() -> (CoralogixRum, SessionManager, IdleArms) {
        let sm = sessionManager()
        let rum = CoralogixRum(options: options(), sessionManager: sm)
        let arms = IdleArms()
        sm.scheduleIdleCheck = { delay, check in arms.append(delay, check) }
        sm.updateActivityTime()
        return (rum, sm, arms)
    }

    private static func masked(_ raw: String) -> String {
        UrlMasker.Masker(UrlMaskingOptions()).maskViewName(raw)
    }

    private static func expire(_ sm: SessionManager) {
        guard var metadata = sm.sessionMetadata else { return XCTFail("no session to expire") }
        metadata.sessionCreationDate = Date().addingTimeInterval(-3601).timeIntervalSince1970
        sm.sessionMetadata = metadata
    }

    private static func assertStartTime(_ start: Int, of sm: SessionManager,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let seconds = sm.sessionMetadata?.sessionCreationDate ?? 0
        XCTAssertGreaterThan(start, 1_600_000_000_000, "epoch milliseconds, not seconds", file: file, line: line)
        XCTAssertEqual(Double(start), seconds * 1000, accuracy: 1, file: file, line: line)
    }

    private static func assertSessionChanged(_ message: RumToReplay?, sm: SessionManager, kept: Bool, idle: Bool,
                                             file: StaticString = #filePath, line: UInt = #line) {
        guard case let .sessionChanged(id, start, k, i)? = message else {
            return XCTFail("expected SessionChanged, got \(String(describing: message))", file: file, line: line)
        }
        XCTAssertEqual(id, sm.currentSessionId, "the live session", file: file, line: line)
        assertStartTime(start, of: sm, file: file, line: line)
        XCTAssertEqual(k, kept, "kept", file: file, line: line)
        XCTAssertEqual(i, idle, "idle", file: file, line: line)
    }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [RumToReplay] = []
    func record(_ message: RumToReplay) { lock.lock(); recorded.append(message); lock.unlock() }
    func clear() { lock.lock(); recorded = []; lock.unlock() }
    var messages: [RumToReplay] { lock.lock(); defer { lock.unlock() }; return recorded }
}

private final class IdleArms: @unchecked Sendable {
    private let lock = NSLock()
    private var arms: [(delay: TimeInterval, check: () -> Void)] = []
    func append(_ delay: TimeInterval, _ check: @escaping () -> Void) {
        lock.lock(); arms.append((delay, check)); lock.unlock()
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return arms.count }
    var last: (delay: TimeInterval, check: () -> Void)? { lock.lock(); defer { lock.unlock() }; return arms.last }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

// MARK: - Internal flushes and cancel on a queued message

extension RumBusTests {

    /// GUARD. Recovering a stored crash, a stored fatal hang and a held React Native fatal each force an
    /// internal flush; none of them is the app's flush, so none publishes Flushing.
    func testCrashAndFatalRecoveryFlushes_publishNoFlushing() throws {
        let store = CrashDeliveryStore.temporary()
        let session = StoredCrashRecord.Session(id: "S1", creationDate: 1_700_000_000, sampledIn: true)
        // A stored native crash in S1.
        let reporter = try XCTUnwrap(PLCrashReporter(configuration: PLCrashReporterConfig(signalHandlerType: .BSD,
                                                                                         symbolicationStrategy: [])))
        reporter.customData = Data(#"{"v":1,"session":{"session_id":"S1","session_creation_time":1700000000000,"is_session_sampled_in":true}}"#.utf8)
        let report = try ANRThreads.withLiveReportLock { try reporter.generateLiveReportAndReturnError() }
        let crash = CrashReportMapper.map(PLCrashReportReader(report: try PLCrashReport(data: report)))
        try FileManager.default.createDirectory(at: store.copiesDirectory, withIntermediateDirectories: true)
        try report.write(to: store.copiesDirectory.appendingPathComponent("\(crash.crashId).plcrash"))
        // A fatal hang in S1, of an earlier launch.
        store.writeHangMarker(HangMarker(detectedAt: Date(timeIntervalSinceNow: -60), pid: 4242, processStartTime: nil,
                                         session: session,
                                         threads: CrashReportMapper.watchdogThreadsJSON([CrashThread(number: 0, crashed: true, frames: [])]),
                                         liveDelivered: false))
        // A React Native fatal held by an earlier process, never delivered live.
        XCTAssertTrue(store.storeJsFatal(HeldJsFatal(crashId: HeldJsFatal.crashIdPrefix + UUID().uuidString,
                                                     process: ProcessIdentity(pid: 2, startSecond: 2),
                                                     crashTime: Date(timeIntervalSinceNow: -60),
                                                     session: session,
                                                     fields: ErrorFields(domain: "", message: "undefined is not a function",
                                                                         isCrash: true, errorType: "TypeError"),
                                                     liveDelivered: nil)))

        let manager = SessionManager(snapshotStore: .relaunched(after: SessionSnapshotRecord(
            sessionId: "S1", errorCount: 0, viewCount: 1, actionCount: 0, hasRecording: false, viewName: "Home",
            viewNumber: 0, appName: "TestApp", appVersion: "1.0", osVersion: "17.0")))
        manager.lastLaunchSession = nil
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []), sessionManager: manager)
        defer { rum.shutdown() }
        let uploader = RecordingUploader()
        rum.crashDeliveryStore = store
        rum.ownProcess = ProcessIdentity(pid: 1, startSecond: 1)
        try XCTUnwrap(rum.coralogixExporter).spanUploader = uploader
        let clock = ManualDeliveryClock()
        let scheduler = CrashDeliveryScheduler(store: store, sender: rum, clock: clock,
                                               backgroundTasks: FakeBackgroundTasks(), isOnline: { true })
        rum.crashDeliveryScheduler = scheduler
        let rec = subscribeAndSkipCurrentState()

        rum.recoverPendingCrashes()
        let recovered = expectation(description: "recovery complete")
        rum.completeCrashRecovery { recovered.fulfill() }
        scheduler.waitUntilAnswered()
        while let next = clock.nextDate {
            clock.advance(to: next)
            scheduler.waitUntilAnswered()
        }
        wait(for: [recovered], timeout: 10)
        CoralogixRum.drainBus()

        XCTAssertEqual(uploader.crashCount, 3, "fixture: the crash, the hang and the JS fatal were each sent")
        XCTAssertFalse(rec.messages.contains(.flushing), "an internal flush published Flushing: \(rec.messages)")
    }

    /// GUARD. A message already queued for a subscription is not delivered once it is cancelled.
    func testCancel_dropsAMessageAlreadyQueued() {
        let rum = CoralogixRum(options: Self.options())
        defer { rum.shutdown() }
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        subscriptions.append(CoralogixRum.subscribe { message in
            guard message == .viewChanged(screen: "Hold") else { return }
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
        })
        let second = Recorder()
        let secondSub = CoralogixRum.subscribe { second.record($0) }
        subscriptions.append(secondSub)
        CoralogixRum.drainBus()
        second.clear()

        rum.setView(name: "Hold")      // the first subscription's handler now holds the bus queue
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success, "fixture: the bus queue is held")
        rum.setView(name: "Queued")    // queued behind it, for both subscriptions
        secondSub.cancel()
        release.signal()
        CoralogixRum.drainBus()

        XCTAssertEqual(second.messages, [], "a cancelled subscription got a message queued before cancel()")
    }
}

/// Counts the crash events RUM sends; answers every request as delivered.
private final class RecordingUploader: SpanUploading, @unchecked Sendable {
    private let lock = NSLock()
    private var crashes = 0
    var crashCount: Int { lock.lock(); defer { lock.unlock() }; return crashes }

    func upload(_ spans: [[String: Any]], endPoint: String, kind: SpanUploadKind) -> SpanUploadResult {
        let sent = spans.filter { event in
            let cxRum = (event[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any]
            return (cxRum?[Keys.errorContext.rawValue] as? [String: Any])?[Keys.isCrash.rawValue] as? Bool == true
        }.count
        lock.lock(); crashes += sent; lock.unlock()
        return .delivered
    }
}
