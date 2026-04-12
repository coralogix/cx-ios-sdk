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
        CoralogixCustomGlobalSpanRegistry.shared.teardownIfNeeded()
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

    func testCustomSpansStampEventTypeSourceSeverityLikeBrowserSdk() {
        let rum = CoralogixRum(options: options!)
        let tracer = rum.getCustomTracer()
        guard let global = tracer.startGlobalSpan(name: "g") else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }

        guard let globalData = (global.span as? any ReadableSpan)?.toSpanData() else {
            return XCTFail("Expected ReadableSpan")
        }
        XCTAssertEqual(globalData.attributes[Keys.eventType.rawValue], .string(CoralogixEventType.customSpan.rawValue))
        XCTAssertEqual(globalData.attributes[Keys.source.rawValue], .string(Keys.code.rawValue))
        XCTAssertEqual(globalData.attributes[Keys.severity.rawValue], .int(CoralogixLogSeverity.info.rawValue))

        let child = global.startCustomSpan(name: "c")
        defer { child.endSpan() }

        guard let childData = (child.span as? any ReadableSpan)?.toSpanData() else {
            return XCTFail("Expected ReadableSpan")
        }
        XCTAssertEqual(childData.attributes[Keys.eventType.rawValue], .string(CoralogixEventType.customSpan.rawValue))
        XCTAssertEqual(childData.attributes[Keys.source.rawValue], .string(Keys.code.rawValue))
        XCTAssertEqual(childData.attributes[Keys.severity.rawValue], .int(CoralogixLogSeverity.info.rawValue))
    }

    /// Nested custom spans must carry session/user attributes so `SessionContext` succeeds during export (otherwise the child is dropped and only the global appears in RUM).
    func testStartCustomSpanIncludesSessionMetadataLikeGlobal() {
        let rum = CoralogixRum(options: options!)
        let tracer = rum.getCustomTracer()
        guard let global = tracer.startGlobalSpan(name: "g") else {
            return XCTFail("Expected global span")
        }
        guard let globalData = (global.span as? any ReadableSpan)?.toSpanData() else {
            return XCTFail("Expected ReadableSpan")
        }
        let child = global.startCustomSpan(name: "c")
        guard let childData = (child.span as? any ReadableSpan)?.toSpanData() else {
            return XCTFail("Expected ReadableSpan")
        }
        XCTAssertEqual(childData.attributes[Keys.sessionId.rawValue], globalData.attributes[Keys.sessionId.rawValue])
        XCTAssertEqual(
            childData.attributes[Keys.sessionCreationDate.rawValue],
            globalData.attributes[Keys.sessionCreationDate.rawValue]
        )
        child.endSpan()
        global.endSpan()
    }

    func testStartGlobalSpanAppliesNameLabelsAndSessionMetadata() {
        let rum = CoralogixRum(options: options!)
        let tracer = rum.getCustomTracer()
        guard let global = tracer.startGlobalSpan(name: "checkout", labels: ["flow": "standard"]) else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }

        guard let readable = global.span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let data = readable.toSpanData()
        XCTAssertEqual(data.name, "checkout")
        guard case let .string(json)? = data.attributes[Keys.customLabels.rawValue],
              let dict = Helper.convertJsonStringToDict(jsonString: json) else {
            return XCTFail("Expected custom_labels JSON on span")
        }
        XCTAssertEqual(dict["flow"] as? String, "standard")
        XCTAssertNotNil(data.attributes[Keys.sessionId.rawValue])
    }

    /// CX-35953: SDK `labels` → `startGlobalSpan` labels → `startCustomSpan` labels (each level overrides on key clash).
    func testCustomSpanLabelsThreeLevelMergeIntoCustomLabelsJSON() {
        let opts = CoralogixExporterOptions(
            coralogixDomain: CoralogixDomain.US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp-CustomSpans",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: ["tier": "sdk", "onlySdk": "1"],
            sessionSampleRate: 100,
            debug: true
        )
        let rum = CoralogixRum(options: opts)
        let tracer = rum.getCustomTracer()
        guard let global = tracer.startGlobalSpan(name: "g", labels: ["tier": "global", "fromGlobal": "yes"]) else {
            return XCTFail("Expected global span")
        }
        guard let globalJson = (global.span as? any ReadableSpan)?.toSpanData().attributes[Keys.customLabels.rawValue],
              case let .string(globalStr) = globalJson,
              let globalDict = Helper.convertJsonStringToDict(jsonString: globalStr)
        else {
            return XCTFail("Expected global custom_labels")
        }
        XCTAssertEqual(globalDict["tier"] as? String, "global")
        XCTAssertEqual(globalDict["onlySdk"] as? String, "1")
        XCTAssertEqual(globalDict["fromGlobal"] as? String, "yes")

        let child = global.startCustomSpan(name: "c", labels: ["tier": "child", "fromChild": "c"])
        guard let childJson = (child.span as? any ReadableSpan)?.toSpanData().attributes[Keys.customLabels.rawValue],
              case let .string(childStr) = childJson,
              let childDict = Helper.convertJsonStringToDict(jsonString: childStr)
        else {
            return XCTFail("Expected child custom_labels")
        }
        XCTAssertEqual(childDict["tier"] as? String, "child")
        XCTAssertEqual(childDict["onlySdk"] as? String, "1")
        XCTAssertEqual(childDict["fromGlobal"] as? String, "yes")
        XCTAssertEqual(childDict["fromChild"] as? String, "c")
        child.endSpan()
        global.endSpan()
    }

    func testStartCustomSpanIsChildOfGlobalSpan() {
        let rum = CoralogixRum(options: options!)
        let tracer = rum.getCustomTracer()
        guard let global = tracer.startGlobalSpan(name: "parent") else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }

        let custom = global.startCustomSpan(name: "child")
        defer { custom.endSpan() }

        guard let childReadable = custom.span as? any ReadableSpan else {
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
        XCTAssertTrue(
            (OpenTelemetry.instance.contextProvider.activeSpan as AnyObject?) === (global.span as AnyObject),
            "startGlobalSpan must register the span as active OTel context"
        )
        let before = OpenTelemetry.instance.contextProvider.activeSpan
        global.withContext {
            XCTAssertTrue(
                (OpenTelemetry.instance.contextProvider.activeSpan as AnyObject?) === (global.span as AnyObject),
                "withContext must keep global as active when it already was"
            )
        }
        XCTAssertEqual(
            OpenTelemetry.instance.contextProvider.activeSpan?.context.spanId,
            before?.context.spanId
        )
        global.endSpan()
    }

    func testSecondStartGlobalSpanReturnsNilUntilFirstEnds() {
        let rum = CoralogixRum(options: options!)
        let tracer = rum.getCustomTracer()
        guard let first = tracer.startGlobalSpan(name: "first") else {
            return XCTFail("Expected first global span")
        }
        XCTAssertNil(tracer.startGlobalSpan(name: "second"))
        first.endSpan()
        guard let third = tracer.startGlobalSpan(name: "third") else {
            return XCTFail("Expected new global after first ended")
        }
        third.endSpan()
    }

    func testEndSpanRestoresPreviousActiveSpan() {
        let rum = CoralogixRum(options: options!)
        let tracer = rum.tracerProvider()
        let markerBuilder = tracer.spanBuilder(spanName: "marker")
        _ = markerBuilder.setActive(true)
        let marker = markerBuilder.startSpan()
        XCTAssertTrue(
            (OpenTelemetry.instance.contextProvider.activeSpan as AnyObject?) === (marker as AnyObject)
        )
        guard let global = rum.getCustomTracer().startGlobalSpan(name: "global") else {
            return XCTFail("Expected global span")
        }
        XCTAssertTrue(
            (OpenTelemetry.instance.contextProvider.activeSpan as AnyObject?) === (global.span as AnyObject)
        )
        global.endSpan()
        XCTAssertTrue(
            (OpenTelemetry.instance.contextProvider.activeSpan as AnyObject?) === (marker as AnyObject),
            "endSpan must restore OTel context from before startGlobalSpan"
        )
        marker.end()
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
