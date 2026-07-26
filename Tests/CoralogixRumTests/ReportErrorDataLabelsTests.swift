//
//  ReportErrorDataLabelsTests.swift
//
//  reportError can bundle a `data` dictionary and a `labels` dictionary onto a single
//  error event — so callers no longer need a separate log() call alongside reportError()
//  to attach context.
//

import XCTest
import CoralogixInternal
import Foundation

@testable import Coralogix

final class ReportErrorDataLabelsTests: XCTestCase {

    private var coralogixRum: CoralogixRum!

    override func tearDownWithError() throws {
        coralogixRum?.shutdown()
        coralogixRum = nil
    }

    // MARK: - Fixtures

    private final class StubUploader: SpanUploading {
        private(set) var uploadedBatches: [[[String: Any]]] = []
        func upload(_ spans: [[String: Any]], endPoint: String) -> SpanExporterResultCode {
            uploadedBatches.append(spans)
            return .success
        }
        var uploadedEvents: [[String: Any]] { uploadedBatches.flatMap { $0 } }
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    private func cxRum(of event: [String: Any]) -> [String: Any]? {
        (event[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any]
    }

    /// Drives the real `reportError` API and returns the emitted error event whose
    /// `error_message` matches `expectedMessage`, so unrelated init/lifecycle spans in
    /// the same flush are ignored.
    private func reportAndCaptureErrorEvent(
        expectedMessage: String,
        _ report: (CoralogixRum) -> Void
    ) throws -> (errorContext: [String: Any], cxRum: [String: Any]) {
        coralogixRum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        let uploader = StubUploader()
        coralogixRum.coralogixExporter?.spanUploader = uploader

        report(coralogixRum)
        coralogixRum.flush()

        func matched() -> [String: Any]? {
            uploader.uploadedEvents.first {
                let ec = cxRum(of: $0)?[Keys.errorContext.rawValue] as? [String: Any]
                return (ec?[Keys.errorMessage.rawValue] as? String) == expectedMessage
            }
        }
        XCTAssertTrue(waitUntil { matched() != nil },
                      "reportError must produce an uploaded error event with message \"\(expectedMessage)\"")
        let event = try XCTUnwrap(matched())
        let cx = try XCTUnwrap(cxRum(of: event))
        let errorContext = try XCTUnwrap(cx[Keys.errorContext.rawValue] as? [String: Any])
        return (errorContext, cx)
    }

    // MARK: - Throwable path: data + labels bundled onto the error event

    func test_reportError_error_withDataAndLabels_landOnSameEvent() throws {
        let result = try reportAndCaptureErrorEvent(expectedMessage: "checkout failed") { rum in
            rum.reportError(
                error: NSError(domain: "Checkout", code: 7,
                               userInfo: [NSLocalizedDescriptionKey: "checkout failed"]),
                data: ["order_id": "A-1001", "retryable": true],
                labels: ["team": "payments"]
            )
        }

        let data = try XCTUnwrap(result.errorContext[Keys.data.rawValue] as? [String: Any],
                                 "data must be attached to the error event's error_context")
        XCTAssertEqual(data["order_id"] as? String, "A-1001")
        XCTAssertEqual(data["retryable"] as? Bool, true)

        let labels = try XCTUnwrap(result.cxRum[Keys.labels.rawValue] as? [String: Any],
                                   "labels must merge into cx_rum.labels on the error event")
        XCTAssertEqual(labels["team"] as? String, "payments")
    }

    func test_reportError_error_usesErrorDescriptionAsMessage() throws {
        // The error's own description is the event's error_message.
        let result = try reportAndCaptureErrorEvent(expectedMessage: "the original description") { rum in
            rum.reportError(
                error: NSError(domain: "Checkout", code: 7,
                               userInfo: [NSLocalizedDescriptionKey: "the original description"])
            )
        }
        XCTAssertEqual(result.errorContext[Keys.errorMessage.rawValue] as? String, "the original description")
    }

    // MARK: - NSException overload carries data/labels

    func test_reportError_exception_withDataAndLabels() throws {
        let result = try reportAndCaptureErrorEvent(expectedMessage: "unhandled reason") { rum in
            let exception = NSException(name: .genericException,
                                        reason: "unhandled reason",
                                        userInfo: nil)
            rum.reportError(exception: exception,
                            data: ["screen": "cart"],
                            labels: ["severity_tag": "high"])
        }
        XCTAssertEqual(result.errorContext[Keys.errorMessage.rawValue] as? String, "unhandled reason")
        let data = try XCTUnwrap(result.errorContext[Keys.data.rawValue] as? [String: Any])
        XCTAssertEqual(data["screen"] as? String, "cart")
        let labels = try XCTUnwrap(result.cxRum[Keys.labels.rawValue] as? [String: Any])
        XCTAssertEqual(labels["severity_tag"] as? String, "high")
    }
}
