//
//  TimeMeasurementTrackerTests.swift
//
//  Pure unit coverage for `TimeMeasurementTracker` (CX-28920 / CX-40508).
//  No `CoralogixRum` integration — that path is exercised by T4. These tests
//  drive the tracker directly and assert on the duration tuple it returns
//  from `endMeasurement`.
//
//  Idle-session stubbing mirrors `SessionManagerTests.swift:60` — set
//  `SessionManager.lastActivity` to a date far enough in the past that
//  `isIdle` flips to `true`. The 15-minute idle interval is private to
//  `SessionManager`; sliding the activity timestamp is the supported hook.
//
//  Reference: tech-debt/CX-28920_custom_time_measurement_api.md §6.
//

import XCTest
@testable import Coralogix

final class TimeMeasurementTrackerTests: XCTestCase {

    private var sessionManager: SessionManager!
    private var tracker: TimeMeasurementTracker!

    override func setUp() {
        super.setUp()
        sessionManager = SessionManager()
        tracker = TimeMeasurementTracker(sessionManager: sessionManager)
    }

    override func tearDown() {
        tracker?.teardown()
        tracker = nil
        sessionManager = nil
        super.tearDown()
    }

    // MARK: - Case 1: happy path

    func testHappyPath_durationMatchesElapsedTime() throws {
        tracker.startMeasurement(key: "a", labels: nil)
        Thread.sleep(forTimeInterval: 0.1)
        let result = try XCTUnwrap(tracker.endMeasurement(key: "a"),
                                   "end should return a non-nil duration tuple.")

        // Lower bound: Thread.sleep guarantees ≥100ms, allow 5ms slack for clock skew at the
        // boundary. Upper bound: generous to avoid flakes under CI scheduling pressure — the
        // assertion that matters is "tracker reported at least the sleep duration".
        XCTAssertGreaterThanOrEqual(result.durationMs, 95.0,
                                    "Duration should be ≥95ms (sleep was 100ms).")
        XCTAssertLessThanOrEqual(result.durationMs, 500.0,
                                 "Duration shouldn't be wildly inflated.")
    }

    // MARK: - Case 2: empty key is ignored

    func testStart_emptyKey_isNoOp() {
        tracker.startMeasurement(key: "", labels: nil)

        // Nothing was stored, so end on the same empty key returns nil (empty also no-ops).
        XCTAssertNil(tracker.endMeasurement(key: ""))
        // And end on any other key returns nil since nothing is in flight.
        XCTAssertNil(tracker.endMeasurement(key: "anything"))
    }

    // MARK: - Case 3: whitespace-only key is ignored

    func testStart_whitespaceOnlyKey_isNoOp() {
        tracker.startMeasurement(key: "   ", labels: nil)
        tracker.startMeasurement(key: "\n\t", labels: nil)

        // Both keys trim to empty; end against any whitespace variant returns nil.
        XCTAssertNil(tracker.endMeasurement(key: "   "))
        XCTAssertNil(tracker.endMeasurement(key: "\n\t"))
        XCTAssertNil(tracker.endMeasurement(key: ""))
    }

    // MARK: - Case 4: duplicate start — first wins

    func testStart_duplicateKey_secondIgnored_firstWins() throws {
        tracker.startMeasurement(key: "a", labels: nil)
        Thread.sleep(forTimeInterval: 0.05)
        // Second start should be ignored; if it overwrote the first, the duration
        // below would be ~50ms instead of ~100ms.
        tracker.startMeasurement(key: "a", labels: nil)
        Thread.sleep(forTimeInterval: 0.05)
        let result = try XCTUnwrap(tracker.endMeasurement(key: "a"),
                                   "end should return a non-nil duration tuple.")

        XCTAssertGreaterThanOrEqual(result.durationMs, 95.0,
                                    "Duplicate start must be ignored — duration should reflect the first start (~100ms total), not the second (~50ms).")
    }

    // MARK: - Case 5: end without prior start

    func testEnd_withoutStart_returnsNil() {
        let result = tracker.endMeasurement(key: "never-started")
        XCTAssertNil(result)
    }

    // MARK: - Case 6: double-end — second is no-op

    func testEnd_doubleEnd_secondReturnsNil() {
        tracker.startMeasurement(key: "a", labels: nil)

        let first = tracker.endMeasurement(key: "a")
        XCTAssertNotNil(first, "First end should succeed.")

        let second = tracker.endMeasurement(key: "a")
        XCTAssertNil(second, "Second end on the same key should be a no-op.")
    }

    // MARK: - Case 7: concurrent start/end with different keys

    func testConcurrent_startEndDifferentKeys_allSurvive() {
        let iterations = 100
        let successes = AtomicCounter()

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            let key = "key_\(i)"
            self.tracker.startMeasurement(key: key, labels: nil)
            // Brief simulated work so durations are non-zero and we exercise the
            // monotonic clock under contention.
            let busyUntil = DispatchTime.now().uptimeNanoseconds &+ 1_000_000 // ~1ms
            while DispatchTime.now().uptimeNanoseconds < busyUntil { /* spin */ }
            if let result = self.tracker.endMeasurement(key: key), result.durationMs > 0 {
                successes.increment()
            }
        }

        XCTAssertEqual(successes.value, iterations,
                       "Every concurrent start/end pair must survive and yield a positive duration.")
    }

    // MARK: - Case 8: session-idle reset clears in-flight measurements

    func testSessionIdle_clearsInFlightMeasurements() {
        tracker.startMeasurement(key: "a", labels: nil)

        // Force session idle (mirrors SessionManagerTests.swift:60 pattern — idle interval is
        // 15 min, so sliding lastActivity 16 min into the past flips isIdle to true).
        sessionManager.lastActivity = Date().addingTimeInterval(-(16 * 60))
        XCTAssertTrue(sessionManager.isIdle, "Sanity check: sessionManager should report idle.")

        // Next interaction with the tracker triggers clearIfSessionIdle, which wipes the map
        // before doing anything else. end should report no in-flight measurement.
        let result = tracker.endMeasurement(key: "a")
        XCTAssertNil(result, "Session went idle between start and end — measurement should be cleared.")
    }

    // MARK: - Case 9: trim consistency

    func testTrim_keyWithWhitespace_resolvesToSameKey() {
        tracker.startMeasurement(key: "k ", labels: nil)
        Thread.sleep(forTimeInterval: 0.02)
        let result = tracker.endMeasurement(key: "k")

        XCTAssertNotNil(result, "Trimmed keys should resolve to the same measurement.")
    }

    // MARK: - Case 10: many in-flight measurements, no cap

    func testManyInFlightMeasurements_noCap() {
        let count = 5_000

        for i in 0..<count {
            tracker.startMeasurement(key: "key_\(i)", labels: nil)
        }

        var ended = 0
        for i in 0..<count {
            if tracker.endMeasurement(key: "key_\(i)") != nil {
                ended += 1
            }
        }

        XCTAssertEqual(ended, count, "All \(count) in-flight measurements should be retained — no silent cap.")
    }
}

// MARK: - Test doubles

/// Thread-safe counter for the concurrent test. `OSAtomic*` is deprecated; using NSLock keeps
/// us portable and consistent with the SDK's existing locking convention.
private final class AtomicCounter {
    private let lock = NSLock()
    private var _value = 0

    func increment() {
        lock.lock()
        _value += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}
