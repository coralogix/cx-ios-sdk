//
//  SdkInitLogTests.swift
//
//  End-to-end coverage for the SDK-init log: a span exported through `CoralogixExporter.export()`
//  lands on the wire under `text.cx_rum.internal_context` with the `init` event name. Asserts on
//  the uploaded wire dict via a capturing `SpanUploading` mock.
//

import XCTest
@testable import Coralogix

final class SdkInitLogTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CoralogixRum.isInitialized = false
    }

    func testSdkInit_stillEmitsInitEventName() throws {
        let uploader = CapturingSpanUploader()
        let rum = CoralogixRum(options: makeSamplingOptions(sampleRate: 100, exclude: []))
        defer { rum.shutdown() }

        let exporter = try XCTUnwrap(rum.coralogixExporter)
        exporter.spanUploader = uploader

        _ = exporter.export(spans: [makeSamplingSpan(eventType: .internalKey)], explicitTimeout: nil)

        let internalContext = try XCTUnwrap(uploader.firstInternalContext())
        XCTAssertEqual(internalContext[Keys.event.rawValue] as? String, Keys.initKey.rawValue,
                       "SDK-init log must resolve to the \"init\" event name.")
    }
}
