import XCTest
import CoralogixInternal
@testable import Coralogix

final class CoralogixCustomSpansTests: XCTestCase {
    private var options: CoralogixExporterOptions?

    override func setUpWithError() throws {
        options = CoralogixExporterOptions(
            coralogixDomain: CoralogixDomain.US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp-CustomSpans",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: [:],
            sessionSampleRate: 100,
            debug: true
        )
    }

    override func tearDownWithError() throws {
        options = nil
        CoralogixRum.isInitialized = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    func testGetCustomTracerPreservesIgnoredInstruments() {
        let rum = CoralogixRum(options: options!)
        let instruments: Set<CoralogixIgnoredInstrument> = [.networkRequests, .errors]
        let tracer = rum.getCustomTracer(ignoredInstruments: instruments)
        XCTAssertEqual(tracer.ignoredInstruments, instruments)
    }

    func testStartGlobalSpanReturnsNilWhenSdkNotInitialized() {
        CoralogixRum.isInitialized = false
        let offOptions = CoralogixExporterOptions(
            coralogixDomain: CoralogixDomain.US2,
            userContext: nil,
            environment: "PROD",
            application: "Off",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: [:],
            sessionSampleRate: 0,
            debug: true
        )
        let rum = CoralogixRum(options: offOptions)
        XCTAssertFalse(rum.isInitialized)
        let tracer = rum.getCustomTracer()
        XCTAssertNil(tracer.startGlobalSpan(name: "root"))
    }

    func testStartGlobalSpanAppliesNameLabelsAndSessionMetadata() {
        let rum = CoralogixRum(options: options!)
        let tracer = rum.getCustomTracer()
        guard let global = tracer.startGlobalSpan(name: "checkout", labels: ["flow": "standard"]) else {
            return XCTFail("Expected global span")
        }
        guard let readable = global.span as? ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let data = readable.toSpanData()
        XCTAssertEqual(data.name, "checkout")
        XCTAssertEqual(data.attributes["flow"], .string("standard"))
        XCTAssertNotNil(data.attributes[Keys.sessionId.rawValue])
    }

    func testStartCustomSpanIsChildOfGlobalSpan() {
        let rum = CoralogixRum(options: options!)
        let tracer = rum.getCustomTracer()
        guard let global = tracer.startGlobalSpan(name: "parent") else {
            return XCTFail("Expected global span")
        }
        let custom = global.startCustomSpan(name: "child")
        guard let childReadable = custom.span as? ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let childData = childReadable.toSpanData()
        XCTAssertEqual(childData.traceId, global.span.context.traceId)
        XCTAssertNotEqual(childData.spanId, global.span.context.spanId)
    }

    func testWithContextSetsActiveSpan() {
        let rum = CoralogixRum(options: options!)
        let tracer = rum.getCustomTracer()
        guard let global = tracer.startGlobalSpan(name: "ctx") else {
            return XCTFail("Expected global span")
        }
        let before = OpenTelemetry.instance.contextProvider.activeSpan
        global.withContext {
            XCTAssertTrue(OpenTelemetry.instance.contextProvider.activeSpan === global.span)
        }
        XCTAssertEqual(
            OpenTelemetry.instance.contextProvider.activeSpan?.context.spanId,
            before?.context.spanId
        )
    }

    func testCustomSpanSetStatusAndEndSpan() {
        let rum = CoralogixRum(options: options!)
        let tracer = rum.getCustomTracer()
        guard let global = tracer.startGlobalSpan(name: "g") else {
            return XCTFail("Expected global span")
        }
        let custom = global.startCustomSpan(name: "c")
        custom.setStatus(.ok)
        XCTAssertTrue(custom.span.status.isOk)
        custom.endSpan()
        global.endSpan()
    }
}
