//
//  ANRDetectorTests.swift
//
//  The watchdog reports the main thread blocked past its threshold, once per hang, with every
//  thread as they were at detection. Most tests block a stand-in main queue, so a hang is exactly
//  as long as the test makes it; the thresholds are scaled down from 5 s / 500 ms.
//

import XCTest
import Foundation
#if canImport(UIKit)
import UIKit
#endif
import CoralogixInternal
@testable import Coralogix

/// Records reported events from any thread.
private final class EventLog: EventReporter {
    private let lock = NSLock()
    private var _events: [ANRErrorEvent] = []
    var events: [ANRErrorEvent] { lock.lock(); defer { lock.unlock() }; return _events }

    func report(_ event: TelemetryEvent) {
        guard let anr = event as? ANRErrorEvent else { return }
        lock.lock(); defer { lock.unlock() }
        _events.append(anr)
    }
}

private final class RecordingUploader: SpanUploading {
    private let lock = NSLock()
    private var _events: [[String: Any]] = []
    var errorContexts: [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return _events.compactMap {
            let cxRum = ($0[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any]
            return cxRum?[Keys.errorContext.rawValue] as? [String: Any]
        }
    }

    func upload(_ spans: [[String: Any]], endPoint: String, kind: SpanUploadKind) -> SpanUploadResult {
        lock.lock(); defer { lock.unlock() }
        _events.append(contentsOf: spans)
        return .delivered
    }
}

private final class Flag {
    private let lock = NSLock()
    private var _value: Bool
    init(_ value: Bool) { _value = value }
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}

private final class Offset {
    private let lock = NSLock()
    private var _seconds: TimeInterval = 0
    var seconds: TimeInterval {
        get { lock.lock(); defer { lock.unlock() }; return _seconds }
        set { lock.lock(); defer { lock.unlock() }; _seconds = newValue }
    }
}

final class ANRDetectorTests: XCTestCase {

    private let threshold: TimeInterval = 0.5
    private let poll: TimeInterval = 0.05

    private var main: DispatchQueue!
    private var center: NotificationCenter!
    private var log: EventLog!
    private var debugger: Flag!
    private var uptimeOffset: Offset!
    private var detector: ANRDetector!

    override func setUp() {
        super.setUp()
        main = DispatchQueue(label: "anr-tests.main")
        center = NotificationCenter()
        log = EventLog()
        debugger = Flag(false)
        uptimeOffset = Offset()
        detector = makeDetector()
    }

    override func tearDown() {
        detector.stopMonitoring()
        detector = nil
        super.tearDown()
    }

    private func makeDetector(mainQueue: DispatchQueue? = nil,
                              captureThreads: @escaping () -> String? = { "threads-at-detection" }) -> ANRDetector {
        let debugger = self.debugger!
        let offset = self.uptimeOffset!
        return ANRDetector(threshold: threshold, pollInterval: poll,
                           uptime: { ProcessInfo.processInfo.systemUptime + offset.seconds },
                           mainQueue: mainQueue ?? main,
                           isDebuggerAttached: { debugger.value },
                           captureThreads: captureThreads,
                           notificationCenter: center,
                           eventReporter: log)
    }

    /// Blocks the stand-in main queue for `seconds`, and returns once it has answered again.
    private func hang(for seconds: TimeInterval) {
        main.async { Thread.sleep(forTimeInterval: seconds) }
        main.sync {}
    }

    /// Lets the detector run for `seconds` with the main queue free.
    private func idle(for seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // MARK: - Detection

    func test_aHangPastTheThreshold_isOneANR_withTheThreadsAtDetection() {
        detector.startMonitoring()
        idle(for: 0.2)

        hang(for: 1.2)
        idle(for: 0.2)

        XCTAssertEqual(log.events.count, 1, "one hang, one ANR however long it lasts")
        let anr = log.events.first
        XCTAssertEqual(anr?.errorMessage, "Application Not Responding for at least 1000 ms.")
        XCTAssertEqual(anr?.errorType, "ANR")
        XCTAssertEqual(anr?.threads, "threads-at-detection")
    }

    func test_aHangShorterThanTheThreshold_isNoANR() {
        detector.startMonitoring()
        idle(for: 0.2)

        hang(for: 0.3)
        idle(for: 0.3)

        XCTAssertTrue(log.events.isEmpty)
    }

    /// Margins are wide: a slow CI runner delays the timer and the queues by hundreds of ms.
    func test_twoSeparateHangs_areTwoANRs() {
        detector.startMonitoring()
        idle(for: 0.3)

        hang(for: 1.5)
        idle(for: 0.6)
        hang(for: 1.5)
        idle(for: 0.4)

        XCTAssertEqual(log.events.count, 2)
    }

    /// The timer it replaced was scheduled on the run loop of the thread that started it, so
    /// started off the main thread it never fired.
    func test_startedFromABackgroundQueue_detectsAHangOfTheRealMainThread() {
        detector = makeDetector(mainQueue: .main)
        let started = expectation(description: "started")
        DispatchQueue.global().async {
            self.detector.startMonitoring()
            started.fulfill()
        }
        wait(for: [started], timeout: 1)
        idle(for: 0.2)

        Thread.sleep(forTimeInterval: 1.0)  // this is the main thread
        idle(for: 0.1)

        XCTAssertEqual(log.events.count, 1)
    }

    // MARK: - Debugger

    func test_underADebugger_noANR_evenIfItDetachesDuringTheHang() {
        debugger.value = true
        detector.startMonitoring()
        idle(for: 0.2)

        main.async { Thread.sleep(forTimeInterval: 1.4) }
        idle(for: 0.8)  // detected under the debugger
        debugger.value = false
        main.sync {}
        idle(for: 0.2)

        XCTAssertTrue(log.events.isEmpty)

        hang(for: 0.9)
        idle(for: 0.2)
        XCTAssertEqual(log.events.count, 1, "the next hang, with no debugger, is reported")
    }

    // MARK: - App state

    #if canImport(UIKit)
    func test_inTheBackground_noANR_andWatchingResumesInTheForeground() {
        detector.startMonitoring()
        idle(for: 0.2)

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        hang(for: 0.9)
        idle(for: 0.2)
        XCTAssertTrue(log.events.isEmpty)

        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        // Wide margins: the watchdog restarts asynchronously, and a slow CI runner needs them.
        idle(for: 0.5)
        hang(for: 1.5)
        idle(for: 0.3)
        XCTAssertEqual(log.events.count, 1)
    }

    /// A watchdog seeded as paused at launch sees no willEnterForeground, only didBecomeActive.
    func test_inTheBackground_watchingResumesOnBecomingActive() {
        detector.startMonitoring()
        idle(for: 0.2)

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        hang(for: 0.9)
        idle(for: 0.2)
        XCTAssertTrue(log.events.isEmpty)

        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        // Wide margins: the watchdog restarts asynchronously, and a slow CI runner needs them.
        idle(for: 0.5)
        hang(for: 1.5)
        idle(for: 0.3)
        XCTAssertEqual(log.events.count, 1)
    }

    /// Inactive is not background: a system alert or Control Center over a hung app is still an ANR.
    func test_whileInactive_aHangIsStillAnANR() {
        detector.startMonitoring()
        idle(for: 0.2)

        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        hang(for: 0.9)
        idle(for: 0.2)

        XCTAssertEqual(log.events.count, 1)
    }

    func test_stopWhilePaused_thenStartAgain_watches() {
        detector.startMonitoring()
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        detector.stopMonitoring()
        XCTAssertFalse(detector.isMonitoring)

        detector.startMonitoring()
        idle(for: 0.2)
        hang(for: 0.9)
        idle(for: 0.2)
        XCTAssertEqual(log.events.count, 1, "a fresh start is not paused")
    }
    #endif

    /// Suspended, the process does not run; on resuming, the time it spent suspended is not a hang.
    func test_aGapBetweenTicks_isASuspension_notAHang() {
        detector.startMonitoring()
        idle(for: 0.2)

        uptimeOffset.seconds = 30
        idle(for: 0.3)

        XCTAssertTrue(log.events.isEmpty)
    }

    /// Only the main thread answering re-arms detection, as on Android.
    func test_aGapDuringAReportedHang_isStillOneANR() {
        detector.startMonitoring()
        idle(for: 0.2)

        main.async { Thread.sleep(forTimeInterval: 2.0) }
        idle(for: 0.8)
        XCTAssertEqual(log.events.count, 1)
        uptimeOffset.seconds = 30
        main.sync {}
        idle(for: 0.3)

        XCTAssertEqual(log.events.count, 1, "the same hang is reported once")
    }

    func test_aReportSlowerThanTwoPolls_isStillOneANR() {
        detector.stopMonitoring()
        detector = makeDetector(captureThreads: { Thread.sleep(forTimeInterval: 0.2); return "threads" })
        detector.startMonitoring()
        idle(for: 0.2)

        hang(for: 2.0)
        idle(for: 0.3)

        XCTAssertEqual(log.events.count, 1, "the same hang is reported once")
    }

    // MARK: - Start and stop

    func test_startTwice_isOneWatchdog_andStopFromAnyThreadEndsIt() {
        detector.startMonitoring()
        detector.startMonitoring()
        idle(for: 0.2)

        let stopped = expectation(description: "stopped")
        DispatchQueue.global().async {
            self.detector.stopMonitoring()
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 1)
        XCTAssertFalse(detector.isMonitoring)

        hang(for: 0.9)
        idle(for: 0.2)
        XCTAssertTrue(log.events.isEmpty, "stopped: nothing is watched")
    }

    func test_startingASecondWatchdog_stopsTheFirst() {
        let first = makeDetector()
        first.startMonitoring()
        detector.startMonitoring()

        XCTAssertFalse(first.isMonitoring)
        XCTAssertTrue(detector.isMonitoring)
    }

    func test_aThresholdBelowTwoPolls_isRaisedToTwoPolls() {
        let detector = ANRDetector(threshold: 0.05, pollInterval: 0.1)
        XCTAssertEqual(detector.threshold, 0.2, accuracy: 0.0001)
    }

    func test_defaults_areFiveSecondsPolledEveryHalfSecond() {
        let detector = ANRDetector()
        XCTAssertEqual(detector.threshold, 5)
        XCTAssertEqual(detector.pollInterval, 0.5)
    }

    // MARK: - Through the SDK

    /// Without session replay the ANR does not wait for a screenshot: it is ended on the
    /// watchdog's queue during the hang, and reaches the wire as a non-crash error with every thread.
    func test_anANR_reachesTheWire_asANonCrashErrorWithEveryThread() throws {
        let sdk = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        defer { sdk.shutdown() }
        sdk.metricsManager.anrDetector?.stopMonitoring()  // the SDK's own, at 5 s on the real main thread
        let uploader = RecordingUploader()
        try XCTUnwrap(sdk.coralogixExporter).spanUploader = uploader
        let reporter = try XCTUnwrap(sdk.metricsManager.eventReporter, "ANR instrumentation is on by default")
        detector = ANRDetector(threshold: threshold, pollInterval: poll, mainQueue: main,
                               isDebuggerAttached: { false }, notificationCenter: center, eventReporter: reporter)
        detector.startMonitoring()
        idle(for: 0.2)

        hang(for: 1.0)
        let flushed = expectation(description: "flushed")
        sdk.flush { flushed.fulfill() }
        wait(for: [flushed], timeout: 10)

        let anrs = uploader.errorContexts.filter { $0[Keys.errorType.rawValue] as? String == "ANR" }
        XCTAssertEqual(anrs.count, 1)
        let anr = try XCTUnwrap(anrs.first)
        XCTAssertEqual(anr[Keys.errorMessage.rawValue] as? String, "Application Not Responding for at least 1000 ms.")
        XCTAssertEqual(anr[Keys.isCrash.rawValue] as? Bool, false)
        let threads = try XCTUnwrap(anr[Keys.threads.rawValue] as? [[[String: Any]]])
        XCTAssertGreaterThan(threads.count, 1)
    }

    // MARK: - Threads

    func test_watchdogThreads_areMainFirst_thenTheRest_eachCappedAt200Frames() throws {
        func frames(_ count: Int) -> [CrashStackFrame] {
            (0..<count).map { CrashStackFrame(frameNumber: "\($0)", binary: "App", functionAddressCalled: "0x1",
                                              base: "0x0", offset: "1") }
        }
        let threads = [
            CrashThread(number: 2, crashed: true, frames: frames(3)),
            CrashThread(number: 0, crashed: false, frames: frames(250)),
            CrashThread(number: 1, crashed: false, frames: frames(5))
        ]

        let json = CrashReportMapper.watchdogThreadsJSON(threads)

        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String])
        let counts = try decoded.map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [Any]).count }
        XCTAssertEqual(counts, [200, 5, 3], "main (thread 0) first, then 1 and 2; the crashed flag is the watchdog's own")
    }

    /// Each live report suspends every other thread: two watchdogs capturing at once (two SDK
    /// instances, say) would suspend each other for good.
    func test_capturesAtTheSameTime_takeTurns_andAllFinish() {
        let finished = expectation(description: "every capture finished")
        finished.expectedFulfillmentCount = 4
        for _ in 0..<4 {
            DispatchQueue.global().async {
                XCTAssertNotNil(ANRThreads.capture())
                finished.fulfill()
            }
        }
        wait(for: [finished], timeout: 30)
    }

    func test_capture_readsEveryThreadOfTheProcess() throws {
        let json = try XCTUnwrap(ANRThreads.capture())
        let threads = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String])
        XCTAssertGreaterThan(threads.count, 1)
    }
}
