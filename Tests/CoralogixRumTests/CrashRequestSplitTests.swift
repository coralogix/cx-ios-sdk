//
//  CrashRequestSplitTests.swift
//
//  A stored crash travels in a request of its own and records what became of it: delivered,
//  refused, dropped by policy (including the native beforeSend) or left to retry. An idle
//  session no longer holds it back, and tracesExporter sees it once per process.
//

import XCTest
import CoralogixInternal

@testable import Coralogix

final class CrashRequestSplitTests: XCTestCase {

    private var coralogixRum: CoralogixRum?

    override func tearDownWithError() throws {
        coralogixRum?.shutdown()
        coralogixRum = nil
    }

    /// Records every request and answers each one through `respond`.
    private final class RoutingUploader: SpanUploading {
        var respond: ([[String: Any]]) -> SpanUploadResult = { _ in .delivered }
        private(set) var requests: [(spans: [[String: Any]], kind: SpanUploadKind)] = []

        func upload(_ spans: [[String: Any]], endPoint: String, kind: SpanUploadKind) -> SpanUploadResult {
            requests.append((spans, kind))
            return respond(spans)
        }
    }

    private static let rejected413 = SpanUploadResult(disposition: .permanentReject, httpStatus: 413, retryAfter: nil, countsAsFailedUpload: false)
    private static let serverError = SpanUploadResult(disposition: .retryable, httpStatus: 503, retryAfter: nil, countsAsFailedUpload: true)

    private func makeCrashSpan(id: String) -> SpanData {
        let attributes: [String: AttributeValue] = [
            Keys.eventType.rawValue: AttributeValue(CoralogixEventType.error.rawValue),
            Keys.severity.rawValue: AttributeValue("5"),
            Keys.source.rawValue: AttributeValue("console"),
            Keys.environment.rawValue: AttributeValue("test"),
            Keys.sessionId.rawValue: AttributeValue("session_001"),
            Keys.sessionCreationDate.rawValue: AttributeValue("1609459200"),
            Keys.errorMessage.rawValue: AttributeValue("crash-\(id)"),
            Keys.isCrash.rawValue: AttributeValue.bool(true),
            Keys.crashEventId.rawValue: AttributeValue(id)
        ]
        return SpanData(traceId: TraceId.random(), spanId: SpanId.random(), name: "crash-\(id)",
                        kind: .client, startTime: Date(), attributes: attributes, endTime: Date(), hasEnded: true)
    }

    private func isCrash(_ event: [String: Any]) -> Bool {
        let text = event[Keys.text.rawValue] as? [String: Any]
        let cxRum = text?[Keys.cxRum.rawValue] as? [String: Any]
        let errorContext = cxRum?[Keys.errorContext.rawValue] as? [String: Any]
        return errorContext?[Keys.isCrash.rawValue] as? Bool ?? false
    }

    private func makeExporter(_ options: CoralogixExporterOptions = makeSamplingOptions(sampleRate: 100, exclude: []))
        throws -> (CoralogixExporter, RoutingUploader) {
        let rum = CoralogixRum(options: options)
        coralogixRum = rum
        let exporter = try XCTUnwrap(rum.coralogixExporter)
        let uploader = RoutingUploader()
        exporter.spanUploader = uploader
        return (exporter, uploader)
    }

    // MARK: - One request per crash

    func test_eachStoredCrash_goesInARequestOfItsOwn() throws {
        let (exporter, uploader) = try makeExporter()

        _ = exporter.export(spans: [makeCrashSpan(id: "A"),
                                    makeSamplingSpan(eventType: .networkRequest),
                                    makeCrashSpan(id: "B")],
                            explicitTimeout: nil)

        let crashRequests = uploader.requests.filter { $0.spans.contains(where: isCrash) }
        XCTAssertEqual(crashRequests.count, 2, "one request per crash")
        XCTAssertTrue(crashRequests.allSatisfy { $0.spans.count == 1 }, "a crash request carries that crash alone")
        XCTAssertTrue(crashRequests.allSatisfy { $0.kind == .storedCrash }, "a crash uses the stored-crash timeouts")

        let liveRequests = uploader.requests.filter { !$0.spans.contains(where: isCrash) }
        XCTAssertEqual(liveRequests.count, 1)
        XCTAssertEqual(liveRequests.first?.kind, .live)
        XCTAssertEqual(exporter.crashUploadOutcome(id: "A"), .delivered)
        XCTAssertEqual(exporter.crashUploadOutcome(id: "B"), .delivered)
    }

    func test_413OnTheLiveBatch_doesNotRejectTheCrash() throws {
        let (exporter, uploader) = try makeExporter()
        uploader.respond = { [unowned self] spans in spans.contains(where: self.isCrash) ? .delivered : Self.rejected413 }

        let result = exporter.export(spans: [makeCrashSpan(id: "crash"), makeSamplingSpan(eventType: .networkRequest)],
                                     explicitTimeout: nil)

        XCTAssertEqual(result, .failure, "the live batch failed, so the export reports failure")
        XCTAssertEqual(exporter.crashUploadOutcome(id: "crash"), .delivered)
        XCTAssertTrue(exporter.didConfirmCrashUpload(id: "crash"))
    }

    // MARK: - Outcomes

    func test_crashRefusedWith4xx_isFinished_soItIsNotSentAgain() throws {
        let (exporter, uploader) = try makeExporter()
        uploader.respond = { _ in Self.rejected413 }

        _ = exporter.export(spans: [makeCrashSpan(id: "too-big")], explicitTimeout: nil)

        XCTAssertEqual(exporter.crashUploadOutcome(id: "too-big"), .rejected)
        XCTAssertTrue(exporter.didConfirmCrashUpload(id: "too-big"))
    }

    func test_crashAnswered5xx_isLeftToRetry_andCounted() throws {
        let (exporter, uploader) = try makeExporter()
        uploader.respond = { _ in Self.serverError }

        _ = exporter.export(spans: [makeCrashSpan(id: "retry")], explicitTimeout: nil)

        XCTAssertEqual(exporter.crashUploadOutcome(id: "retry"), .failed(counted: true))
        XCTAssertFalse(exporter.didConfirmCrashUpload(id: "retry"))
    }

    func test_aFinishedCrash_isNotReopenedByALaterFailure() throws {
        let (exporter, uploader) = try makeExporter()
        let span = makeCrashSpan(id: "once")

        _ = exporter.export(spans: [span], explicitTimeout: nil)
        uploader.respond = { _ in Self.serverError }
        _ = exporter.export(spans: [makeCrashSpan(id: "once")], explicitTimeout: nil)

        XCTAssertEqual(exporter.crashUploadOutcome(id: "once"), .delivered)
    }

    func test_nativeBeforeSendDroppingTheCrash_isPolicyDropped_andPurged() throws {
        var options = makeSamplingOptions(sampleRate: 100, exclude: [])
        // Native beforeSend receives the cx_rum dictionary itself, not the `text` wrapper.
        options.beforeSend = { cxRum in
            let errorContext = cxRum[Keys.errorContext.rawValue] as? [String: Any]
            return errorContext?[Keys.isCrash.rawValue] as? Bool == true ? nil : cxRum
        }
        let (exporter, uploader) = try makeExporter(options)

        let result = exporter.export(spans: [makeCrashSpan(id: "dropped"), makeSamplingSpan(eventType: .networkRequest)],
                                     explicitTimeout: nil)

        XCTAssertEqual(result, .success)
        XCTAssertFalse(uploader.requests.contains { $0.spans.contains(where: isCrash) }, "the crash is never sent")
        XCTAssertEqual(uploader.requests.count, 1, "the live span still goes out")
        XCTAssertEqual(exporter.crashUploadOutcome(id: "dropped"), .policyDropped)
        XCTAssertTrue(exporter.didConfirmCrashUpload(id: "dropped"), "a crash the customer dropped is finished with")
    }

    func test_nativeBeforeSendDroppingEverything_stillResolvesTheCrash() throws {
        var options = makeSamplingOptions(sampleRate: 100, exclude: [])
        options.beforeSend = { _ in nil }
        let (exporter, uploader) = try makeExporter(options)

        _ = exporter.export(spans: [makeCrashSpan(id: "all-dropped")], explicitTimeout: nil)

        XCTAssertTrue(uploader.requests.isEmpty)
        XCTAssertEqual(exporter.crashUploadOutcome(id: "all-dropped"), .policyDropped)
    }

    // MARK: - Idle session

    func test_idleSession_dropsLiveSpans_butStillSendsAndSettlesAStoredCrash() throws {
        let (exporter, uploader) = try makeExporter()
        let sessionManager = try XCTUnwrap(coralogixRum?.sessionManager)
        sessionManager.lastActivity = Date().addingTimeInterval(-20 * 60)
        XCTAssertTrue(sessionManager.isIdle, "Precondition: the session is idle.")

        let result = exporter.export(spans: [makeCrashSpan(id: "idle-crash"), makeSamplingSpan(eventType: .networkRequest)],
                                     explicitTimeout: nil)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(uploader.requests.count, 1, "only the crash goes out")
        XCTAssertTrue(uploader.requests.first?.spans.contains(where: isCrash) ?? false)
        XCTAssertEqual(exporter.crashUploadOutcome(id: "idle-crash"), .delivered)
    }

    func test_idleSession_withNoCrash_sendsNothing() throws {
        let (exporter, uploader) = try makeExporter()
        let sessionManager = try XCTUnwrap(coralogixRum?.sessionManager)
        sessionManager.lastActivity = Date().addingTimeInterval(-20 * 60)

        let result = exporter.export(spans: [makeSamplingSpan(eventType: .networkRequest)], explicitTimeout: nil)

        XCTAssertEqual(result, .success)
        XCTAssertTrue(uploader.requests.isEmpty)
    }

    // MARK: - tracesExporter

    func test_aCrashSentTwice_reachesTracesExporterOnce() throws {
        var forwardedNames: [String] = []
        let options = makeSamplingOptions(sampleRate: 100, exclude: [], tracesExporter: { data in
            let names = data.tracesData.resourceSpans
                .flatMap { $0.scopeSpans }
                .flatMap { $0.spans }
                .map { $0.name }
            forwardedNames.append(contentsOf: names)
        })
        let (exporter, uploader) = try makeExporter(options)
        uploader.respond = { _ in Self.serverError }

        _ = exporter.export(spans: [makeCrashSpan(id: "twice")], explicitTimeout: nil)
        uploader.respond = { _ in .delivered }
        _ = exporter.export(spans: [makeCrashSpan(id: "twice")], explicitTimeout: nil)

        XCTAssertEqual(uploader.requests.count, 2, "the crash is sent both times")
        XCTAssertEqual(forwardedNames.filter { $0 == "crash-twice" }.count, 1, "but forwarded once")
    }
}
