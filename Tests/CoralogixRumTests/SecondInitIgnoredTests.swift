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
//  2. The guard is the FIRST statement of `init`: when an instance is live — exactly when
//     `CoralogixRum.getConfig() != nil`, i.e. `isInitialized && liveInstance != nil` — the init logs
//     `Log.w("CoralogixRum is already initialized!")` and returns. Nothing before it runs: no
//     `mobileSDK` write, no `Log.isDebug` write, no session manager, exporter, tracer provider, swizzle,
//     instrumentation, crash recovery, bus handler or `liveInstance` change. The warning is gated by the
//     live `Log.isDebug`, as Android's is by the live debug flag.
//     "Live" includes the weak `liveInstance`: an instance the host dropped without `shutdown()` is
//     deallocated (probed) and can no longer be shut down, so a later init is NOT ignored (today's behaviour).
//  3. `private var isInert = false`, set on the ignored path. Exactly two members read it:
//       - `public var isInitialized: Bool` → `!isInert && CoralogixRum.isInitialized` (the inert instance says false);
//       - `shutdown()` returns at once when `isInert` (today any instance's shutdown flips the process-wide flag,
//         retires the bus and silences the live instance).
//     Every other public instance method is already a no-op on the inert instance because it holds no exporter,
//     options, session manager or tracer provider (probed: with only 1–3 in place, every test here is green, and
//     an inert `reportError` reaches no uploader). No per-method guard rewrite, no forwarding to the live instance.
//  4. Unchanged: `shutdown()` on the live instance, then a new init → a fully live SDK with the new options.
//
//  No new symbol: every test compiles today; all but the two marked GUARD fail by assertion (reason on each).
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

    private static func options(application: String, key: String = "test-key", debug: Bool = false) -> CoralogixExporterOptions {
        CoralogixExporterOptions(coralogixDomain: .US2, environment: "test", application: application,
                                 version: "1.0", publicKey: key, debug: debug)
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
