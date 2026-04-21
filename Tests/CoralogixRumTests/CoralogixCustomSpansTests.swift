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
            traceParentInHeader: [Keys.enable.rawValue: true],
            debug: true
        )
    }

    override func tearDownWithError() throws {
        CoralogixCustomGlobalSpanRegistry.shared.teardownIfNeeded()
        options = nil
        CoralogixRum.isInitialized = false
        CoralogixRum.resetCustomTracerIssuanceForTesting()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    func testGetCustomTracerPreservesIgnoredInstruments() {
        let rum = CoralogixRum(options: options!)
        let instruments: Set<CoralogixIgnoredInstrument> = [.networkRequests, .errors]
        guard let tracer = rum.getCustomTracer(ignoredInstruments: instruments) else {
            return XCTFail("Expected custom tracer")
        }
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
        XCTAssertNil(rum.getCustomTracer())
    }

    func testCustomSpansStampEventTypeSourceSeverityLikeBrowserSdk() {
        let rum = CoralogixRum(options: options!)
        guard let tracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
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
        guard let tracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
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
        guard let tracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
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
            traceParentInHeader: [Keys.enable.rawValue: true],
            debug: true
        )
        let rum = CoralogixRum(options: opts)
        guard let tracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
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
        guard let tracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
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
        guard let tracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
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

    /// CX-35957: When another span is active, `withContext` restores global as active so nested `startCustomSpan` inherits global trace/parent.
    func testWithContextChildSpanInheritsGlobalTraceWhenGlobalWasNotActive() {
        let rum = CoralogixRum(options: options!)
        let tracer = rum.tracerProvider()
        guard let customTracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = customTracer.startGlobalSpan(name: "g") else {
            return XCTFail("Expected global span")
        }
        guard let globalData = (global.span as? any ReadableSpan)?.toSpanData() else {
            return XCTFail("Expected ReadableSpan")
        }
        let markerBuilder = tracer.spanBuilder(spanName: "marker")
        _ = markerBuilder.setActive(true)
        let marker = markerBuilder.startSpan()
        XCTAssertFalse(
            (OpenTelemetry.instance.contextProvider.activeSpan as AnyObject?) === (global.span as AnyObject),
            "Precondition: marker span must replace global as OTel active span"
        )
        global.withContext {
            let child = global.startCustomSpan(name: "inside_ctx")
            defer { child.endSpan() }
            guard let childData = (child.span as? any ReadableSpan)?.toSpanData() else {
                XCTFail("Expected ReadableSpan")
                return
            }
            XCTAssertEqual(childData.traceId, globalData.traceId)
            XCTAssertEqual(childData.parentSpanId, globalData.spanId)
        }
        marker.end()
        global.endSpan()
    }

    /// CX-35957: After `endSpan()` on a global, the next `startGlobalSpan` is a new root with a new trace id.
    func testNewGlobalSpanAfterEndGetsFreshTraceId() {
        let rum = CoralogixRum(options: options!)
        guard let customTracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
        guard let first = customTracer.startGlobalSpan(name: "first") else {
            return XCTFail("Expected first global")
        }
        guard let firstData = (first.span as? any ReadableSpan)?.toSpanData() else {
            return XCTFail("Expected ReadableSpan")
        }
        first.endSpan()
        guard let second = customTracer.startGlobalSpan(name: "second") else {
            return XCTFail("Expected second global after first ended")
        }
        defer { second.endSpan() }
        guard let secondData = (second.span as? any ReadableSpan)?.toSpanData() else {
            return XCTFail("Expected ReadableSpan")
        }
        XCTAssertNotEqual(firstData.traceId, secondData.traceId, "New global span must not reuse ended global's trace id")
    }

    func testSecondStartGlobalSpanReturnsNilUntilFirstEnds() {
        let rum = CoralogixRum(options: options!)
        guard let tracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
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
        guard let tracerForGlobal = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracerForGlobal.startGlobalSpan(name: "global") else {
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
        guard let tracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "g") else {
            return XCTFail("Expected global span")
        }
        let custom = global.startCustomSpan(name: "c")
        custom.setStatus(.ok)
        XCTAssertTrue(custom.span.status.isOk)
        custom.endSpan()
        global.endSpan()
    }

    // MARK: - CX-35956 (getCustomTracer guards)

    func testGetCustomTracer_nilWhenTraceParentNotConfigured() {
        let opts = CoralogixExporterOptions(
            coralogixDomain: CoralogixDomain.US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: [:],
            sessionSampleRate: 100,
            debug: true
        )
        let rum = CoralogixRum(options: opts)
        XCTAssertNil(rum.getCustomTracer())
    }

    func testGetCustomTracer_nilWhenTraceParentEnableFalse() {
        let opts = CoralogixExporterOptions(
            coralogixDomain: CoralogixDomain.US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: [:],
            sessionSampleRate: 100,
            traceParentInHeader: [Keys.enable.rawValue: false],
            debug: true
        )
        let rum = CoralogixRum(options: opts)
        XCTAssertNil(rum.getCustomTracer())
    }

    func testGetCustomTracer_singletonSecondCallReturnsNil() {
        let rum = CoralogixRum(options: options!)
        XCTAssertNotNil(rum.getCustomTracer())
        XCTAssertNil(rum.getCustomTracer())
    }

    func testGetCustomTracer_availableAgainAfterShutdown() {
        let rum = CoralogixRum(options: options!)
        XCTAssertNotNil(rum.getCustomTracer())
        XCTAssertNil(rum.getCustomTracer())
        rum.shutdown()
        let rum2 = CoralogixRum(options: options!)
        XCTAssertNotNil(rum2.getCustomTracer())
    }

    // MARK: - CX-35954 / CX-35955 (registry + makeSpan parent policy)

    /// Registry exposes ignored flags only while a global span from that tracer is active.
    func testRegistry_shouldBreakTraceInheritance_matchesIgnoredInstrumentsOnGlobalSpan() {
        let rum = CoralogixRum(options: options!)
        guard let tracer = rum.getCustomTracer(ignoredInstruments: [.errors, .networkRequests]) else {
            return XCTFail("Expected custom tracer")
        }
        XCTAssertFalse(
            CoralogixCustomGlobalSpanRegistry.shared.shouldBreakTraceInheritance(for: .errors),
            "No global yet — nothing ignored for propagation"
        )
        guard let global = tracer.startGlobalSpan(name: "g") else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }
        XCTAssertTrue(CoralogixCustomGlobalSpanRegistry.shared.shouldBreakTraceInheritance(for: .errors))
        XCTAssertTrue(CoralogixCustomGlobalSpanRegistry.shared.shouldBreakTraceInheritance(for: .networkRequests))
        XCTAssertFalse(CoralogixCustomGlobalSpanRegistry.shared.shouldBreakTraceInheritance(for: .userInteractions))
    }

    func testRegistry_shouldBreakTraceInheritance_falseAfterGlobalEnds() {
        let rum = CoralogixRum(options: options!)
        guard let tracer = rum.getCustomTracer(ignoredInstruments: [.userInteractions]) else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "g") else {
            return XCTFail("Expected global span")
        }
        XCTAssertTrue(CoralogixCustomGlobalSpanRegistry.shared.shouldBreakTraceInheritance(for: .userInteractions))
        global.endSpan()
        XCTAssertFalse(CoralogixCustomGlobalSpanRegistry.shared.shouldBreakTraceInheritance(for: .userInteractions))
    }

    /// CX-35955: `makeSpan` for an ignored event type uses `setNoParent()` — new trace, no parent.
    func testMakeSpan_ignoredUserInteraction_breaksGlobalTrace() {
        let rum = CoralogixRum(options: options!)
        guard let tracer = rum.getCustomTracer(ignoredInstruments: [.userInteractions]) else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "g") else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }
        guard let globalReadable = global.span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let globalData = globalReadable.toSpanData()

        let span = rum.makeSpan(event: .userInteraction, source: .console, severity: .info)
        defer { span.end() }
        guard let readable = span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let data = readable.toSpanData()
        XCTAssertNotEqual(data.traceId, globalData.traceId)
        XCTAssertNil(data.parentSpanId)
    }

    /// CX-35954: event types not listed in `ignoredInstruments` still parent under the global when it is the active span (default OTel current span).
    func testMakeSpan_navigationWithGlobalActive_inheritsGlobalTrace() {
        let rum = CoralogixRum(options: options!)
        guard let tracer = rum.getCustomTracer(ignoredInstruments: [.networkRequests]) else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "g") else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }
        guard let globalReadable = global.span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let globalData = globalReadable.toSpanData()

        let span = rum.makeSpan(event: .navigation, source: .console, severity: .info)
        defer { span.end() }
        guard let readable = span as? any ReadableSpan else {
            return XCTFail("Expected ReadableSpan")
        }
        let data = readable.toSpanData()
        XCTAssertEqual(data.traceId, globalData.traceId)
        XCTAssertEqual(data.parentSpanId, globalData.spanId)
    }

    // MARK: - [String: Any] label merge tests

    /// Mixed-type values (Int, Bool, String) survive merge and JSON serialization to custom_labels.
    func testGlobalSpanLabels_mixedTypes_surviveJsonSerialization() {
        let rum = CoralogixRum(options: options!)
        guard let tracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
        let labels: [String: Any] = ["name": "checkout", "retryCount": 3, "isGuest": true]
        guard let global = tracer.startGlobalSpan(name: "g", labels: labels) else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }
        guard let readable = global.span as? any ReadableSpan,
              case let .string(json)? = readable.toSpanData().attributes[Keys.customLabels.rawValue],
              let dict = Helper.convertJsonStringToDict(jsonString: json) else {
            return XCTFail("Expected custom_labels JSON on global span")
        }
        XCTAssertEqual(dict["name"] as? String, "checkout")
        XCTAssertEqual(dict["retryCount"] as? Int, 3)
        XCTAssertEqual(dict["isGuest"] as? Bool, true)
    }

    /// Child span labels with mixed types survive three-level merge and JSON serialization.
    func testChildSpanLabels_mixedTypes_surviveJsonSerialization() {
        let rum = CoralogixRum(options: options!)
        guard let tracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "g", labels: ["count": 10]) else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }
        let child = global.startCustomSpan(name: "c", labels: ["ratio": 0.75, "active": false])
        defer { child.endSpan() }
        guard let readable = child.span as? any ReadableSpan,
              case let .string(json)? = readable.toSpanData().attributes[Keys.customLabels.rawValue],
              let dict = Helper.convertJsonStringToDict(jsonString: json) else {
            return XCTFail("Expected custom_labels JSON on child span")
        }
        XCTAssertEqual(dict["count"] as? Int, 10)
        XCTAssertEqual(dict["ratio"] as? Double, 0.75)
        XCTAssertEqual(dict["active"] as? Bool, false)
    }

    /// Layer overrides base on key collision (layer wins), even with mixed types.
    func testLabelMerge_layerOverridesBase_mixedTypes() {
        let rum = CoralogixRum(options: options!)
        guard let tracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "g", labels: ["tier": "global", "count": 5]) else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }
        let child = global.startCustomSpan(name: "c", labels: ["tier": "child", "count": 99])
        defer { child.endSpan() }
        guard let readable = child.span as? any ReadableSpan,
              case let .string(json)? = readable.toSpanData().attributes[Keys.customLabels.rawValue],
              let dict = Helper.convertJsonStringToDict(jsonString: json) else {
            return XCTFail("Expected custom_labels JSON")
        }
        XCTAssertEqual(dict["tier"] as? String, "child")
        XCTAssertEqual(dict["count"] as? Int, 99)
    }

    /// nil layer returns base unchanged (no crash, no empty labels).
    func testLabelMerge_nilLayer_returnsBaseUnchanged() {
        let rum = CoralogixRum(options: options!)
        guard let tracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "g", labels: ["env": "prod"]) else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }
        let child = global.startCustomSpan(name: "c", labels: nil)
        defer { child.endSpan() }
        guard let readable = child.span as? any ReadableSpan,
              case let .string(json)? = readable.toSpanData().attributes[Keys.customLabels.rawValue],
              let dict = Helper.convertJsonStringToDict(jsonString: json) else {
            return XCTFail("Expected custom_labels JSON")
        }
        XCTAssertEqual(dict["env"] as? String, "prod")
    }

    /// Empty layer returns base unchanged.
    func testLabelMerge_emptyLayer_returnsBaseUnchanged() {
        let rum = CoralogixRum(options: options!)
        guard let tracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "g", labels: ["env": "staging"]) else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }
        let child = global.startCustomSpan(name: "c", labels: [:])
        defer { child.endSpan() }
        guard let readable = child.span as? any ReadableSpan,
              case let .string(json)? = readable.toSpanData().attributes[Keys.customLabels.rawValue],
              let dict = Helper.convertJsonStringToDict(jsonString: json) else {
            return XCTFail("Expected custom_labels JSON")
        }
        XCTAssertEqual(dict["env"] as? String, "staging")
    }

    /// Three-level merge: SDK labels → global labels → child labels, each level wins on collision.
    func testLabelMerge_threeLevels_mixedTypes_eachLevelWinsOnCollision() {
        let opts = CoralogixExporterOptions(
            coralogixDomain: CoralogixDomain.US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp-CustomSpans",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: ["tier": "sdk", "sdkOnly": 42, "flag": false],
            sessionSampleRate: 100,
            traceParentInHeader: [Keys.enable.rawValue: true],
            debug: true
        )
        let rum = CoralogixRum(options: opts)
        guard let tracer = rum.getCustomTracer() else {
            return XCTFail("Expected custom tracer")
        }
        guard let global = tracer.startGlobalSpan(name: "g", labels: ["tier": "global", "globalOnly": 99]) else {
            return XCTFail("Expected global span")
        }
        defer { global.endSpan() }
        let child = global.startCustomSpan(name: "c", labels: ["tier": "child", "childOnly": true])
        defer { child.endSpan() }
        guard let readable = child.span as? any ReadableSpan,
              case let .string(json)? = readable.toSpanData().attributes[Keys.customLabels.rawValue],
              let dict = Helper.convertJsonStringToDict(jsonString: json) else {
            return XCTFail("Expected custom_labels JSON on child")
        }
        XCTAssertEqual(dict["tier"] as? String, "child")
        XCTAssertEqual(dict["sdkOnly"] as? Int, 42)
        XCTAssertEqual(dict["flag"] as? Bool, false)
        XCTAssertEqual(dict["globalOnly"] as? Int, 99)
        XCTAssertEqual(dict["childOnly"] as? Bool, true)
    }
}
