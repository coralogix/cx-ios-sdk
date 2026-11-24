import XCTest
@testable import Coralogix

final class LifeCycleInstrumentationTests: XCTestCase {
    var options: CoralogixExporterOptions?
    var coralogixRum: CoralogixRum?

    override func setUpWithError() throws {
        options = CoralogixExporterOptions(
            coralogixDomain: CoralogixDomain.US2,
            userContext: nil,
            environment: "TEST",
            application: "TestApp-iOS",
            version: "1.0",
            publicKey: "test-token",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: [:],
            sessionSampleRate: 100,
            debug: false
        )
    }

    override func tearDownWithError() throws {
        coralogixRum?.shutdown()
        coralogixRum = nil
        options = nil
        CoralogixRum.isInitialized = false
        // A hybrid init rewrites this process-wide static; later tests expect native.
        CoralogixRum.mobileSDK = MobileSDK(sdkFramework: .swift)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    // MARK: - Snapshot on the background event (encoded payload)

    func testBackgroundEvent_insideThrottleWindow_isUploadedAsSnapshotEvent() throws {
        let uploader = CapturingSpanUploader()
        try startSession(uploadingTo: uploader)

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        let event = try XCTUnwrap(waitForLifeCycleEvent(.appDidEnterBackgroundNotification, in: uploader.cxRumPayloads),
                                  "The background event must reach the uploader")
        XCTAssertEqual(event[Keys.isSnapshotEvent.rawValue] as? Bool, true)
        XCTAssertNotNil(event[Keys.snapshotContext.rawValue] as? [String: Any])
    }

    func testBecomeActiveEvent_insideThrottleWindow_isUploadedWithoutSnapshot() throws {
        let uploader = CapturingSpanUploader()
        try startSession(uploadingTo: uploader)

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        let event = try XCTUnwrap(waitForLifeCycleEvent(.appDidBecomeActiveNotification, in: uploader.cxRumPayloads),
                                  "Control: the become-active event must reach the uploader")
        XCTAssertNil(event[Keys.isSnapshotEvent.rawValue], "The flag is only written on snapshot events")
        XCTAssertNil(event[Keys.snapshotContext.rawValue])
    }

    /// The hybrid callback here never answers, like JS/Dart that is suspended or killed before the
    /// round trip finishes. The background event must still be uploaded, with its snapshot.
    func testHybridBackgroundEvent_uploadsDirectlyAsSnapshotEvent_withoutBeforeSendAnswering() throws {
        for framework in [SdkFramework.flutter(version: "1.0.0"), .reactNative(version: "1.0.0")] {
            let capture = EncodedEventCapture()
            let uploader = CapturingSpanUploader()
            var hybridOptions = try XCTUnwrap(options)
            hybridOptions.beforeSendCallBack = capture.append
            try startSession(options: hybridOptions, sdkFramework: framework, uploadingTo: uploader)

            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

            let event = try XCTUnwrap(waitForLifeCycleEvent(.appDidEnterBackgroundNotification, in: uploader.cxRumPayloads),
                                      "\(framework): the background event must upload without the round trip")
            XCTAssertEqual(event[Keys.isSnapshotEvent.rawValue] as? Bool, true, "\(framework)")
            XCTAssertNotNil(event[Keys.snapshotContext.rawValue] as? [String: Any], "\(framework)")
            XCTAssertNotNil(waitForLifeCycleEvent(.appDidBecomeActiveNotification, in: capture.cxRumPayloads),
                            "\(framework): other life-cycle events still take the beforeSend round trip")

            coralogixRum?.shutdown()
            coralogixRum = nil
            CoralogixRum.isInitialized = false
        }
    }

    /// The background flush ends its background task when the export returns, so the event must
    /// already be uploaded by then, not left waiting on a callback that may never answer.
    func testHybridExport_backgroundEventIsUploadedBeforeExportReturns() throws {
        let capture = EncodedEventCapture()
        let uploader = CapturingSpanUploader()
        var hybridOptions = try XCTUnwrap(options)
        hybridOptions.beforeSendCallBack = capture.append
        let rum = CoralogixRum(options: hybridOptions, sdkFramework: .reactNative(version: "1.0.0"))
        coralogixRum = rum
        let exporter = try XCTUnwrap(rum.coralogixExporter)
        exporter.spanUploader = uploader
        drainPendingSpans()
        let uploadedBefore = uploader.cxRumPayloads().count

        let background = makeSamplingSpan(
            eventType: .lifeCycle,
            extraAttributes: [Keys.type.rawValue: AttributeValue(Keys.appDidEnterBackgroundNotification.rawValue)])
        let result = exporter.export(spans: [background, makeSamplingSpan(eventType: .networkRequest)], explicitTimeout: nil)

        XCTAssertEqual(result, .success)
        let uploaded = Array(uploader.cxRumPayloads().dropFirst(uploadedBefore))
        XCTAssertEqual(uploaded.map(Self.lifeCycleType), [Keys.appDidEnterBackgroundNotification.rawValue],
                       "Only the background event uploads directly, before export returns")
        XCTAssertTrue(capture.cxRumPayloads().contains { Self.eventType(of: $0) == CoralogixEventType.networkRequest.rawValue },
                      "The network event still goes to beforeSend")
    }

    private static func eventType(of cxRum: [String: Any]) -> String? {
        (cxRum[Keys.eventContext.rawValue] as? [String: Any])?[Keys.type.rawValue] as? String
    }

    /// Starts a sampled-in session whose snapshot throttle has just been stamped, so only a forced
    /// snapshot can put one on the next plain event. Without the stamp, the first event after init
    /// gets a snapshot anyway (nil throttle) and the assertions above would pass without the fix.
    private func startSession(options: CoralogixExporterOptions? = nil,
                              sdkFramework: SdkFramework = .swift,
                              uploadingTo uploader: SpanUploading) throws {
        let rum = CoralogixRum(options: try XCTUnwrap(options ?? self.options), sdkFramework: sdkFramework)
        coralogixRum = rum
        try XCTUnwrap(rum.coralogixExporter).spanUploader = uploader
        XCTAssertTrue(rum.isInstrumentationInstalled(.lifeCycle), "Precondition: life-cycle events are installed")

        drainPendingSpans()
        let sessionManager = try XCTUnwrap(rum.sessionManager)
        sessionManager.lastActivity = Date()
        sessionManager.lastSnapshotEventTime = Date()
    }

    private func drainPendingSpans() {
        Thread.sleep(forTimeInterval: 0.3)
        (OpenTelemetry.instance.tracerProvider as? TracerProviderSdk)?.forceFlush(timeout: 3)
        Thread.sleep(forTimeInterval: 0.3)
    }

    private func waitForLifeCycleEvent(_ type: Keys,
                                       in cxRumPayloads: () -> [[String: Any]],
                                       timeout: TimeInterval = 5) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let match = cxRumPayloads().first(where: { Self.lifeCycleType(of: $0) == type.rawValue }) {
                return match
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return nil
    }

    private static func lifeCycleType(of cxRum: [String: Any]) -> String? {
        (cxRum[Keys.lifeCycleContext.rawValue] as? [String: Any])?[Keys.eventName.rawValue] as? String
    }

    func testBackgroundNotificationTriggersFlush() {
        guard let options else {
            XCTFail("Options not initialized")
            return
        }

        coralogixRum = CoralogixRum(options: options)
        XCTAssertTrue(CoralogixRum.isInitialized)

        // Post the background notification to verify it triggers flush without crashing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
        }

        let completionExpectation = expectation(description: "background flush should complete")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation], timeout: 5.0)
    }

    func testLifeCycleInstrumentationDoesNotCrash() {
        guard let options else {
            XCTFail("Options not initialized")
            return
        }

        coralogixRum = CoralogixRum(options: options)
        XCTAssertTrue(CoralogixRum.isInitialized)

        coralogixRum?.log(severity: .info, message: "test log")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
        }

        let backgroundFlushExpectation = expectation(description: "background should not crash")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            backgroundFlushExpectation.fulfill()
        }

        wait(for: [backgroundFlushExpectation], timeout: 5.0)
    }
}

/// Thread-safe collector of the encoded batches a hybrid `beforeSendCallBack` receives.
private final class EncodedEventCapture {
    private let lock = NSLock()
    private var collected: [[String: Any]] = []

    func append(_ batch: [[String: Any]]) {
        lock.lock()
        defer { lock.unlock() }
        collected.append(contentsOf: batch)
    }

    func cxRumPayloads() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return collected.compactMap { ($0[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any] }
    }
}
