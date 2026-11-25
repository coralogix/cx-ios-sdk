//
//  SecondInitIgnoredTests.swift
//
//  CX-71257: one SDK per process, as on Android 3.0.0 (`CoralogixRum.initialize` returns early and logs
//  "CoralogixRum is already initialized!"). A second `CoralogixRum(options:…)` while an instance is live —
//  no `shutdown()` between — is ignored: the live SDK keeps running unchanged and the new object is inert.
//
//  HEADER CONTRACT — the only production changes this file sanctions (all in `CoralogixRum.swift`):
//
//  1. `public init(options:sdkFramework:sessionManager:)` — the `sessionManager` parameter becomes
//     `@autoclosure () -> SessionManager? = SessionManager.forLaunch()`, evaluated ONLY on the path that
//     initializes. Why: evaluating `SessionManager.forLaunch()` mints a session and rewrites the crash
//     context's session to it (probed: the live id was replaced by the orphan's), so a default argument
//     evaluated before the guard would misfile the live session's crashes. Call sites stay source-compatible.
//  2. The guard is the FIRST statement of `init` (N1 + N4). Check and claim are ONE hold of the existing
//     `liveInstanceLock` (not a call to `getConfig()`, which takes the same non-reentrant lock):
//         liveInstanceLock.lock()
//         let busy = (isInitialized && liveInstance != nil) || initClaimed
//         if !busy { initClaimed = true }
//         liveInstanceLock.unlock()
//         guard !busy else { isInert = true; Log.w("CoralogixRum is already initialized!"); return }
//         defer { liveInstanceLock.lock(); initClaimed = false; liveInstanceLock.unlock() }
//     with `private static var initClaimed = false` (guarded by `liveInstanceLock`). The claim is released by the
//     `defer`, i.e. after `attachBus` has set `liveInstance`, and also when startup returns early. No lock is held
//     across startup; `getConfig()` and `shutdown()` are unchanged (shutdown is not serialized). The racer that
//     loses is inert at once — it never waits.
//     Nothing before the guard runs: no `mobileSDK` write, no `Log.isDebug` write, no session manager, exporter,
//     tracer provider, swizzle, instrumentation, crash recovery, bus handler or `liveInstance` change. The warning
//     is gated by the live `Log.isDebug`, as Android's is by the live debug flag.
//     "Live" includes the weak `liveInstance`: an instance the host dropped without `shutdown()` is deallocated
//     (probed) and can no longer be shut down, so a later init is NOT ignored (today's behaviour).
//  3. `private var isInert = false`, set on the ignored path.
//       - `public var isInitialized: Bool` → `!isInert && CoralogixRum.isInitialized` (the inert instance says false);
//       - every `guard CoralogixRum.isInitialized` in an INSTANCE method becomes `guard self.isInitialized`, so that
//         property is the one choke point (`flush`'s `if CoralogixRum.isInitialized` likewise). Without it,
//         `sendCustomMeasurement`, `setUserInteraction` and `setNetworkRequestContext` reach `makeSpan` through the
//         live global tracer provider and the host's exporter receives session-less spans (4b finding).
//         Not inside escaping `[weak self]` closures (the `topUpInstrumentations` hop keeps its static check);
//       - `shutdown()` returns at once when `isInert` (today any instance's shutdown flips the process-wide flag,
//         retires the bus and silences the live instance).
//     No forwarding to the live instance.
//  4. Unchanged: `shutdown()` on the live instance, then a new init → a fully live SDK with the new options.
//
//  No new symbol: every test compiles today; all but those marked GUARD fail by assertion (reason on each).
//

import XCTest
#if canImport(CoralogixBootstrap)
import CoralogixBootstrap
#endif
@_spi(RumBus) @testable import Coralogix

final class SecondInitIgnoredTests: XCTestCase {

    private var rums: [CoralogixRum] = []
    private var subscriptions: [RumBusSubscription] = []
    private var savedLogger: CXLogger!
    private var savedDebug = false

    override func setUp() {
        super.setUp()
        savedLogger = Log.shared
        savedDebug = Log.isDebug
        CoralogixRum.isInitialized = false
        // An instance another test left running would still be live: one init + shutdown clears it.
        CoralogixRum(options: Self.options(application: "Reset")).shutdown()
        CoralogixRum.drainBus()
    }

    override func tearDown() {
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        rums.reversed().forEach { $0.shutdown() }
        rums = []
        CoralogixRum.isInitialized = false
        Log.shared = savedLogger
        Log.isDebug = savedDebug
        CoralogixExporter.testExportCallback = nil
        CoralogixRum.mobileSDK = MobileSDK(sdkFramework: .swift)
        super.tearDown()
    }

    // MARK: - The live SDK is unchanged

    /// RED-now: today the second init supersedes the first, so getConfig returns "Second".
    func testSecondInitWhileLive_getConfigKeepsTheFirstOptions() throws {
        start(Self.options(application: "First", key: "key-1"))
        start(Self.options(application: "Second", key: "key-2"))
        let config = try XCTUnwrap(CoralogixRum.getConfig())
        XCTAssertEqual(config.application, "First")
        XCTAssertEqual(config.publicKey, "key-1")
    }

    /// RED-now: today the second instance becomes the live one and registers its own tracer provider.
    func testSecondInitWhileLive_firstInstanceStaysTheLiveOne() throws {
        let first = start(Self.options(application: "First"))
        let sessionId = try XCTUnwrap(first.getSessionId)
        let provider = try XCTUnwrap(first.tracerProviderSdk)

        start(Self.options(application: "Second"))

        XCTAssertTrue(CoralogixRum.liveInstance === first, "the first instance stays the live one")
        XCTAssertTrue(first.isInitialized)
        XCTAssertEqual(first.getSessionId, sessionId, "the live session is not rotated")
        XCTAssertTrue((OpenTelemetry.instance.tracerProvider as AnyObject) === provider,
                      "no second tracer provider is registered")
    }

    /// RED-now: today the second instance builds a full SDK (exporter, session, instrumentations).
    func testSecondInitWhileLive_returnsAnInertInstance() {
        let first = start(Self.options(application: "First"))
        XCTAssertTrue(first.isInstrumentationInstalled(.lifeCycle), "fixture: a live init installs instrumentations")

        let second = start(Self.options(application: "Second"))

        XCTAssertFalse(second.isInitialized, "the ignored instance does not report itself initialized")
        XCTAssertNil(second.coralogixExporter, "no second exporter")
        XCTAssertNil(second.tracerProviderSdk, "no second tracer provider")
        XCTAssertNil(second.sessionManager, "no second session")
        XCTAssertNil(second.getSessionId)
        for type in [CoralogixExporterOptions.InstrumentationType.lifeCycle, .userActions, .network,
                     .errors, .mobileVitals, .anr] {
            XCTAssertFalse(second.isInstrumentationInstalled(type), "no \(type) re-install")
        }
    }

    /// RED-now: today the second init overwrites `mobileSDK`, `Log.isDebug`, and (through the default
    /// `SessionManager.forLaunch()`) the crash context's session.
    func testSecondInitWhileLive_leavesProcessWideStateAlone() throws {
        let first = start(Self.options(application: "First", debug: false), framework: .swift)
        let liveSession = try XCTUnwrap(first.getSessionId)
        XCTAssertEqual(Self.crashContextSessionId(), liveSession, "fixture: the crash context names the live session")

        start(Self.options(application: "Second", debug: true), framework: .flutter(version: "9.9.9"))

        XCTAssertEqual(CoralogixRum.mobileSDK.sdkFramework, .swift, "the framework stays the live one's")
        XCTAssertFalse(Log.isDebug, "debug logging stays the live one's")
        XCTAssertEqual(Self.crashContextSessionId(), liveSession,
                       "crashes still file under the live session (the default session manager must not be built)")
    }

    // MARK: - The warning

    /// RED-now: nothing is logged today.
    func testSecondInitWhileLive_logsAlreadyInitializedWarning() {
        let logger = RecordingLogger()
        Log.shared = logger
        start(Self.options(application: "First", debug: true))
        XCTAssertFalse(logger.contains(Self.warning), "fixture: a first init does not warn")

        start(Self.options(application: "Second", debug: true))

        XCTAssertEqual(logger.entries.filter { $0.message == Self.warning }.map(\.level), [.warning],
                       "exactly one warning, at warning level")
    }

    // MARK: - The bus

    /// RED-now: today the second init gives an existing subscriber a SessionChanged for its session.
    func testSecondInitWhileLive_publishesNothingOnTheBus() {
        start(Self.options(application: "First"))
        let rec = subscribeAndSkipCurrentState()

        start(Self.options(application: "Second"))
        CoralogixRum.drainBus()

        XCTAssertEqual(rec.messages, [])
    }

    // MARK: - The inert instance's methods

    /// RED-now: today the second instance is a full SDK, so its calls change the running options, rotate,
    /// and its shutdown stops RUM for the process.
    func testInertInstanceMethods_changeNothingAndDoNotStopTheLiveSdk() throws {
        let first = start(Self.options(application: "First"))
        let sessionId = try XCTUnwrap(first.getSessionId)
        let rec = subscribeAndSkipCurrentState()
        let inert = start(Self.options(application: "Second"))
        CoralogixRum.drainBus()
        rec.clear()

        inert.set(labels: ["from": "inert"])
        inert.setUserContext(userContext: UserContext(userId: "inert", userName: "i", userEmail: "i@i", userMetadata: [:]))
        inert.setApplicationContext(application: "Renamed", version: "9")
        inert.setView(name: "InertScreen")
        inert.createNewSession()
        inert.log(severity: .info, message: "inert-log")
        inert.reportMobileVitalsMeasurement(type: "cpu", value: 1, units: "%")
        inert.reportMobileVitalsMeasurement(type: "cpu", metrics: [HybridMetric(name: "inert-vital", value: 1, units: "%")])
        inert.startTimeMeasure(name: "inert-measure")
        inert.endTimeMeasure(name: "inert-measure")
        XCTAssertNil(inert.getCustomTracer())
        inert.sendBeforeSendData([["inert": true]])
        XCTAssertEqual(inert.networkRequestSampling(), NetworkRequestSampling(isSampled: false, sessionId: nil),
                       "the inert instance has no session to sample")
        inert.flush()
        inert.shutdown()
        CoralogixRum.drainBus()

        let config = try XCTUnwrap(CoralogixRum.getConfig(), "the inert shutdown must not stop the live SDK")
        XCTAssertEqual(config.application, "First")
        XCTAssertNil(config.labels?["from"])
        XCTAssertNil(config.userContext)
        XCTAssertTrue(first.isInitialized)
        XCTAssertEqual(first.getSessionId, sessionId)
        XCTAssertEqual(rec.messages, [], "nothing on the bus: no ViewChanged, SessionChanged, Flushing or ShuttingDown")
    }

    /// RED-now: today the first instance's report goes through the second's tracer provider (registered
    /// globally), so the live stub never sees it. After the change the live report arrives (the non-vacuous
    /// half) and the inert one does not. GUARD for later changes: an inert instance must not emit through the
    /// live provider.
    func testInertReportError_sendsNothing() {
        let first = start(makeSamplingOptions(sampleRate: 100, exclude: [])) // the fixture ReportErrorDataLabelsTests sends through
        let uploader = StubUploader()
        first.coralogixExporter?.spanUploader = uploader
        let inert = start(Self.options(application: "Second"))

        inert.reportError(exception: NSException(name: .genericException, reason: "from-inert", userInfo: nil))
        first.reportError(exception: NSException(name: .genericException, reason: "from-live", userInfo: nil))
        first.flush()

        XCTAssertTrue(waitUntil { uploader.errorMessages.contains("from-live") },
                      "the live instance reports: \(uploader.errorMessages)")
        XCTAssertFalse(uploader.errorMessages.contains("from-inert"), "\(uploader.errorMessages)")
    }

    /// RED-now (4b): these three reach `makeSpan` through the global tracer provider — the LIVE one — unless
    /// the inert instance's own `isInitialized` stops them, so the host's exporter would receive spans with no
    /// session. The live instance makes the same calls (the non-vacuous half: they do export).
    func testInertMeasurementAndHybridCalls_exportNoSpan() {
        let exported = ExportedTexts()
        CoralogixExporter.testExportCallback = { spans in exported.add(spans.map { "\($0.name) \($0.attributes)" }) }
        // A hybrid framework, so the live instance accepts hybrid interactions.
        let first = start(makeSamplingOptions(sampleRate: 100, exclude: []), framework: .flutter(version: "1.0.0"))
        first.coralogixExporter?.spanUploader = StubUploader()
        let inert = start(Self.options(application: "Second"))

        for (rum, tag) in [(inert, "inert"), (first, "live")] {
            rum.sendCustomMeasurement(name: "\(tag)-measure", value: 1)
            rum.setUserInteraction([Keys.eventName.rawValue: "click", Keys.targetElement.rawValue: "\(tag)-button"])
            rum.setNetworkRequestContext(dictionary: [Keys.url.rawValue: "https://\(tag).example.com/x",
                                                      Keys.method.rawValue: "GET", Keys.statusCode.rawValue: 200])
        }
        first.flush()

        let liveMarkers = ["live-measure", "live-button", "live.example.com"]
        XCTAssertTrue(waitUntil { liveMarkers.allSatisfy { m in exported.texts.contains { $0.contains(m) } } },
                      "the live calls export: \(exported.texts)")
        XCTAssertEqual(exported.texts.filter { $0.contains("inert") }, [], "no span from the inert instance")
    }

    // MARK: - Racing inits (N4)

    /// RED-now: today every racer runs a full startup (8 exporters, 8 sessions, the last one live). After the
    /// change exactly one wins and the rest are inert. 10 rounds, the winner shut down between them.
    func testRacingInits_exactlyOneIsLive_theRestAreInert() {
        let n = 8
        for round in 0..<10 {
            Log.isDebug = true // the racers warn before the winner's own `debug: true` may have landed
            let logger = RecordingLogger()
            Log.shared = logger
            let rec = BusRecorder()
            let subscription = CoralogixRum.subscribe { rec.record($0) }
            let racers = racingInits(n, round: round)
            CoralogixRum.drainBus()
            subscription.cancel()

            let live = racers.filter { $0.isInitialized && $0.coralogixExporter != nil && $0.sessionManager != nil }
            guard live.count == 1, let winner = live.first else {
                XCTFail("round \(round): \(live.count) of \(n) racers are live")
                racers.forEach { $0.shutdown() }
                continue
            }
            for racer in racers where racer !== winner {
                XCTAssertFalse(racer.isInitialized, "round \(round)")
                XCTAssertNil(racer.coralogixExporter, "round \(round)")
                XCTAssertNil(racer.sessionManager, "round \(round)")
            }
            XCTAssertTrue(CoralogixRum.liveInstance === winner, "round \(round)")
            XCTAssertEqual(CoralogixRum.getConfig()?.application, winner.options?.application, "round \(round)")
            XCTAssertTrue((OpenTelemetry.instance.tracerProvider as AnyObject) === winner.tracerProviderSdk, "round \(round)")
            XCTAssertEqual(logger.entries.filter { $0.message == Self.warning }.count, n - 1, "round \(round)")
            XCTAssertEqual(rec.messages.filter { if case .currentState = $0 { return true }; return false }.count, 1,
                           "round \(round): \(rec.messages)")
            XCTAssertEqual(rec.messages.filter { if case .sessionChanged = $0 { return true }; return false }.count, 0,
                           "round \(round): \(rec.messages)")
            winner.shutdown()
        }
    }

    /// RED-now (one live) + GUARD (no deadlock): an init on the main thread racing one on a background queue,
    /// with swizzling on — the background init hops network swizzling to main and waits up to 0.5 s for it.
    func testMainInitRacingABackgroundInit_finishesWithOneLive() {
        for round in 0..<5 {
            let gate = DispatchSemaphore(value: 0)
            let box = RumBox()
            let done = expectation(description: "background init \(round)")
            DispatchQueue.global(qos: .userInitiated).async {
                gate.wait()
                box.rum = CoralogixRum(options: Self.options(application: "Background-\(round)"))
                done.fulfill()
            }
            let started = Date()
            gate.signal()
            let onMain = CoralogixRum(options: Self.options(application: "Main-\(round)"))
            wait(for: [done], timeout: 10)
            XCTAssertLessThan(Date().timeIntervalSince(started), 10, "round \(round)")
            let both = [onMain] + (box.rum.map { [$0] } ?? [])
            rums.append(contentsOf: both)
            XCTAssertEqual(both.filter { $0.isInitialized }.count, 1, "round \(round)")
            both.forEach { $0.shutdown() }
        }
    }

    /// GUARD (passes now): `shutdown()` on a background queue racing an init on main finishes. Shutdown is not
    /// serialized with init (driver ruling), so only completion is pinned here, not which side ends up live.
    func testBackgroundShutdownRacingAMainInit_finishes() {
        for round in 0..<5 {
            let old = start(Self.options(application: "Old-\(round)"))
            let gate = DispatchSemaphore(value: 0)
            let done = expectation(description: "background shutdown \(round)")
            DispatchQueue.global(qos: .userInitiated).async {
                gate.wait()
                old.shutdown()
                done.fulfill()
            }
            let started = Date()
            gate.signal()
            let next = start(Self.options(application: "Next-\(round)"))
            wait(for: [done], timeout: 10)
            XCTAssertLessThan(Date().timeIntervalSince(started), 10, "round \(round)")
            next.shutdown()
            CoralogixRum.isInitialized = false // whichever way the race went, the next round starts from nothing
        }
    }

    // MARK: - Shutdown, then init

    /// GUARD today (passes now) — pins that the change keeps re-init after shutdown working, including
    /// after an ignored init.
    func testShutdownThenInit_takesTheNewOptions_evenAfterAnIgnoredInit() throws {
        let first = start(Self.options(application: "First"))
        start(Self.options(application: "Ignored"))
        first.shutdown()
        XCTAssertNil(CoralogixRum.getConfig(), "fixture: shut down")

        let next = start(Self.options(application: "Next", key: "key-n"))

        XCTAssertTrue(next.isInitialized)
        XCTAssertTrue(CoralogixRum.liveInstance === next)
        XCTAssertNotNil(next.coralogixExporter)
        let config = try XCTUnwrap(CoralogixRum.getConfig())
        XCTAssertEqual(config.application, "Next")
        XCTAssertEqual(config.publicKey, "key-n")
    }

    /// GUARD today (passes now) — pins contract item 2's "live": an instance dropped without `shutdown()` is
    /// gone and can never be shut down, so it must not block a later init. Fails if the guard keys on
    /// `CoralogixRum.isInitialized` alone.
    func testDroppedInstanceWithoutShutdown_doesNotBlockALaterInit() throws {
        weak var dropped: CoralogixRum?
        autoreleasepool {
            let rum = CoralogixRum(options: Self.options(application: "Dropped"))
            dropped = rum
        }
        XCTAssertNil(dropped, "fixture: the dropped instance is deallocated")
        XCTAssertTrue(CoralogixRum.isInitialized, "fixture: nothing shut it down")

        let next = start(Self.options(application: "Next"))

        XCTAssertTrue(next.isInitialized)
        XCTAssertEqual(try XCTUnwrap(CoralogixRum.getConfig()).application, "Next")
    }

    // MARK: - Helpers

    private static let warning = "CoralogixRum is already initialized!"

    @discardableResult
    private func start(_ options: CoralogixExporterOptions, framework: SdkFramework = .swift) -> CoralogixRum {
        let rum = CoralogixRum(options: options, sdkFramework: framework)
        rums.append(rum)
        return rum
    }

    private static func options(application: String, key: String = "test-key", swizzling: Bool = true,
                                debug: Bool = false) -> CoralogixExporterOptions {
        CoralogixExporterOptions(coralogixDomain: .US2, environment: "test", application: application,
                                 version: "1.0", publicKey: key, enableSwizzling: swizzling, debug: debug)
    }

    /// `n` inits released together from background queues; waits with an expectation so the main run loop turns.
    private func racingInits(_ n: Int, round: Int) -> [CoralogixRum] {
        let gate = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var made: [CoralogixRum] = []
        let done = expectation(description: "racers \(round)")
        done.expectedFulfillmentCount = n
        for i in 0..<n {
            DispatchQueue.global(qos: .userInitiated).async {
                gate.wait()
                let rum = CoralogixRum(options: Self.options(application: "Racer-\(round)-\(i)", swizzling: false, debug: true),
                                       sessionManager: SessionManager(snapshotStore: SessionSnapshotStore()))
                lock.lock(); made.append(rum); lock.unlock()
                done.fulfill()
            }
        }
        for _ in 0..<n { gate.signal() }
        wait(for: [done], timeout: 30)
        lock.lock()
        defer { lock.unlock() }
        rums.append(contentsOf: made)
        return made
    }

    private static func crashContextSessionId() -> String? {
        (CRXCrashContext.sections[Keys.crashContextSession.rawValue] as? [String: Any])?[Keys.sessionId.rawValue] as? String
    }

    private func subscribeAndSkipCurrentState(file: StaticString = #filePath, line: UInt = #line) -> BusRecorder {
        let rec = BusRecorder()
        subscriptions.append(CoralogixRum.subscribe { rec.record($0) })
        CoralogixRum.drainBus()
        if case .currentState? = rec.messages.first {} else {
            XCTFail("expected the sticky CurrentState first, got \(rec.messages)", file: file, line: line)
        }
        rec.clear()
        return rec
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }
}

private final class RumBox: @unchecked Sendable {
    var rum: CoralogixRum?
}

private final class ExportedTexts: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    func add(_ texts: [String]) { lock.lock(); recorded.append(contentsOf: texts); lock.unlock() }
    var texts: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
}

private final class BusRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [RumToReplay] = []
    func record(_ message: RumToReplay) { lock.lock(); recorded.append(message); lock.unlock() }
    func clear() { lock.lock(); recorded = []; lock.unlock() }
    var messages: [RumToReplay] { lock.lock(); defer { lock.unlock() }; return recorded }
}

private final class RecordingLogger: CXLogger, @unchecked Sendable {
    struct Entry { let level: LogLevel; let message: String }
    private let lock = NSLock()
    private var recorded: [Entry] = []
    var entries: [Entry] { lock.lock(); defer { lock.unlock() }; return recorded }
    func contains(_ message: String) -> Bool { entries.contains { $0.message == message } }
    func log(level: LogLevel, message: @autoclosure () -> String, metadata: [String: Any]?,
             file: String, function: String, line: Int) {
        let text = message()
        lock.lock(); recorded.append(Entry(level: level, message: text)); lock.unlock()
    }
}

private final class StubUploader: SpanUploading, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [[String: Any]] = []
    func upload(_ spans: [[String: Any]], endPoint: String, kind: SpanUploadKind) -> SpanUploadResult {
        lock.lock(); events.append(contentsOf: spans); lock.unlock()
        return .delivered
    }
    var errorMessages: [String] {
        lock.lock(); defer { lock.unlock() }
        return events.compactMap {
            let cx = ($0[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any]
            return (cx?[Keys.errorContext.rawValue] as? [String: Any])?[Keys.errorMessage.rawValue] as? String
        }
    }
}
