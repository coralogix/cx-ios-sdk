//
//  MaskedHybridInteractionTests.swift
//  CoralogixRumTests
//

import XCTest
import UIKit
import CoralogixInternal
@testable import Coralogix

/// A hybrid-reported interaction (`setUserInteraction`) is redacted and flagged on the same
/// terms as a native one. In hybrid mode the swizzles feed session replay but emit no span —
/// the span comes from the bridge payload, which never passes through `TapDataExtractor` —
/// so masking here resolves from the payload's coordinates against the frame's mask geometry,
/// or from the wrapper's own `is_masked` verdict.
final class MaskedHybridInteractionTests: XCTestCase {

    private var coralogixRum: CoralogixRum!
    private let maskRects = [CGRect(x: 0, y: 0, width: 100, height: 100)]

    override func setUpWithError() throws {
        let options = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "test",
            application: "TestApp",
            version: "1.0.0",
            publicKey: "test-key",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: [:],
            sessionSampleRate: 100,
            debug: false
        )
        coralogixRum = CoralogixRum(options: options)
    }

    override func tearDownWithError() throws {
        SdkManager.shared.register(sessionReplayInterface: nil)
        coralogixRum?.shutdown()
        coralogixRum = nil
    }

    private func clickPayload(x: Double? = nil, y: Double? = nil,
                              extra: [String: Any] = [:]) -> [String: Any] {
        var dict: [String: Any] = [
            Keys.eventName.rawValue: "click",
            Keys.targetElement.rawValue: "Button",
            Keys.elementId.rawValue: "pin_key_7",
            Keys.targetElementInnerText.rawValue: "7"
        ]
        if let x { dict[Keys.positionX.rawValue] = x }
        if let y { dict[Keys.positionY.rawValue] = y }
        dict.merge(extra) { _, new in new }
        return dict
    }

    // MARK: - Geometry resolution

    /// Only the inner text is redacted (web-SDK parity): identity fields and coordinates go
    /// out as-is, and anything stricter is the customer's beforeSend, keyed on the flag.
    func testTapInsideMaskRects_redactsInnerTextOnly_andFlagsTrue() throws {
        let result = try XCTUnwrap(coralogixRum.validateHybridInteraction(
            clickPayload(x: 50, y: 50), maskRects: maskRects))

        XCTAssertEqual(result[Keys.targetElementInnerText.rawValue] as? String, "***")
        XCTAssertEqual(result[Keys.isMaskedElement.rawValue] as? Bool, true)
        XCTAssertEqual(result[Keys.elementId.rawValue] as? String, "pin_key_7",
                       "Identity fields are reported as-is on a masked interaction")
        XCTAssertEqual(result[Keys.positionX.rawValue] as? Double, 50)
        XCTAssertEqual(result[Keys.positionY.rawValue] as? Double, 50)
    }

    func testTapOutsideMaskRects_notRedacted_flagFalse() throws {
        let result = try XCTUnwrap(coralogixRum.validateHybridInteraction(
            clickPayload(x: 200, y: 200), maskRects: maskRects))

        XCTAssertEqual(result[Keys.targetElementInnerText.rawValue] as? String, "7")
        XCTAssertEqual(result[Keys.isMaskedElement.rawValue] as? Bool, false)
    }

    // MARK: - The documented false-on-unknown default

    /// A payload with no coordinates (React Native scroll and swipe carry none) cannot be
    /// resolved — the pinned answer is false, a decision rather than an accident.
    func testNoCoordinates_flagFalse_nothingRedacted() throws {
        let result = try XCTUnwrap(coralogixRum.validateHybridInteraction(
            clickPayload(), maskRects: maskRects))

        XCTAssertEqual(result[Keys.isMaskedElement.rawValue] as? Bool, false)
        XCTAssertEqual(result[Keys.targetElementInnerText.rawValue] as? String, "7")
    }

    /// No frame geometry to test against (no session replay registered) — same pinned false.
    func testNoMaskGeometry_flagFalse() throws {
        SdkManager.shared.register(sessionReplayInterface: nil)

        let result = try XCTUnwrap(coralogixRum.validateHybridInteraction(
            clickPayload(x: 50, y: 50)))

        XCTAssertEqual(result[Keys.isMaskedElement.rawValue] as? Bool, false)
        XCTAssertEqual(result[Keys.targetElementInnerText.rawValue] as? String, "7")
    }

    /// Production path: geometry fetched live from the registered session replay.
    func testLiveMaskGeometry_isFetchedFromRegisteredSessionReplay() throws {
        let mock = MockSessionReplay()
        mock.maskRectsToReturn = maskRects
        SdkManager.shared.register(sessionReplayInterface: mock)
        defer { SdkManager.shared.register(sessionReplayInterface: nil) }

        let result = try XCTUnwrap(coralogixRum.validateHybridInteraction(
            clickPayload(x: 50, y: 50)))

        XCTAssertEqual(result[Keys.isMaskedElement.rawValue] as? Bool, true)
        XCTAssertEqual(result[Keys.targetElementInnerText.rawValue] as? String, "***")
    }

    // MARK: - The wrapper's own verdict

    /// `is_masked` is authoritative for hybrids that own their masking (Flutter): it answers
    /// even when nothing else could...
    func testIsMaskedOverrideTrue_withoutCoordinates_redactsAndFlagsTrue() throws {
        let result = try XCTUnwrap(coralogixRum.validateHybridInteraction(
            clickPayload(extra: [Keys.isMasked.rawValue: true])))

        XCTAssertEqual(result[Keys.isMaskedElement.rawValue] as? Bool, true)
        XCTAssertEqual(result[Keys.targetElementInnerText.rawValue] as? String, "***")
    }

    /// ...and it wins over the geometry in both directions.
    func testIsMaskedOverrideFalse_beatsGeometry() throws {
        let result = try XCTUnwrap(coralogixRum.validateHybridInteraction(
            clickPayload(x: 50, y: 50, extra: [Keys.isMasked.rawValue: false]),
            maskRects: maskRects))

        XCTAssertEqual(result[Keys.isMaskedElement.rawValue] as? Bool, false)
        XCTAssertEqual(result[Keys.targetElementInnerText.rawValue] as? String, "7")
    }

    /// `is_masked` is an input directive, not an attribute — it must not reach the payload.
    func testIsMaskedInputKey_isNotForwarded() throws {
        let result = try XCTUnwrap(coralogixRum.validateHybridInteraction(
            clickPayload(extra: [Keys.isMasked.rawValue: true])))

        XCTAssertNil(result[Keys.isMasked.rawValue],
                     "The bridge's is_masked directive must not appear in interaction_context")
        XCTAssertNotNil(result[Keys.isMaskedElement.rawValue])
    }

    // MARK: - Path parity

    /// The acceptance pin: the same masked tap produces the same redaction and the same flag
    /// whether it arrives from the swizzle or from `setUserInteraction`. A future change to
    /// one path that misses the other fails here.
    func testNativeAndHybridPaths_agreeOnRedactionAndFlag() throws {
        let point = CGPoint(x: 50, y: 50)

        let button = UIButton()
        button.setTitle("7", for: .normal)
        let native = TapDataExtractor.extract(
            from: TouchEvent(view: button, location: point, eventType: .click, scrollDirection: nil),
            maskRects: maskRects)

        let hybrid = try XCTUnwrap(coralogixRum.validateHybridInteraction(
            clickPayload(x: point.x, y: point.y), maskRects: maskRects))

        XCTAssertEqual(native[Keys.targetElementInnerText.rawValue] as? String, "***")
        XCTAssertEqual(hybrid[Keys.targetElementInnerText.rawValue] as? String,
                       native[Keys.targetElementInnerText.rawValue] as? String,
                       "Both paths must apply the same redaction")
        XCTAssertEqual(native[Keys.isMaskedElement.rawValue] as? Bool, true)
        XCTAssertEqual(hybrid[Keys.isMaskedElement.rawValue] as? Bool,
                       native[Keys.isMaskedElement.rawValue] as? Bool,
                       "Both paths must report the same flag")
    }

    /// Unmasked agreement too — parity is not just "both redact everything".
    func testNativeAndHybridPaths_agreeOnUnmaskedTap() throws {
        let point = CGPoint(x: 200, y: 200)

        let button = UIButton()
        button.setTitle("7", for: .normal)
        let native = TapDataExtractor.extract(
            from: TouchEvent(view: button, location: point, eventType: .click, scrollDirection: nil),
            maskRects: maskRects)

        let hybrid = try XCTUnwrap(coralogixRum.validateHybridInteraction(
            clickPayload(x: point.x, y: point.y), maskRects: maskRects))

        XCTAssertEqual(native[Keys.targetElementInnerText.rawValue] as? String, "7")
        XCTAssertEqual(hybrid[Keys.targetElementInnerText.rawValue] as? String, "7")
        XCTAssertEqual(native[Keys.isMaskedElement.rawValue] as? Bool, false)
        XCTAssertEqual(hybrid[Keys.isMaskedElement.rawValue] as? Bool, false)
    }
}

/// `beforeSend` is the customer-side lever the flag exists for: read it, rewrite the
/// interaction, or drop the event entirely.
final class IsMaskedElementBeforeSendTests: XCTestCase {

    private let startTime = Date()

    private func makeInteractionSpan(isMasked: Bool) -> SpanDataProtocol {
        let tapObject: [String: Any] = [
            Keys.eventName.rawValue: "click",
            Keys.targetElement.rawValue: "Button",
            Keys.targetElementInnerText.rawValue: isMasked ? "***" : "7",
            Keys.isMaskedElement.rawValue: isMasked,
            Keys.positionX.rawValue: 50.0,
            Keys.positionY.rawValue: 50.0
        ]
        return MockSpanData(
            attributes: [
                Keys.severity.rawValue: AttributeValue("3"),
                Keys.eventType.rawValue: AttributeValue(CoralogixEventType.userInteraction.rawValue),
                Keys.source.rawValue: AttributeValue("console"),
                Keys.environment.rawValue: AttributeValue("prod"),
                Keys.sessionId.rawValue: AttributeValue("session_001"),
                Keys.sessionCreationDate.rawValue: AttributeValue(1609459200),
                Keys.tapObject.rawValue: AttributeValue(Helper.convertDictionaryToJsonString(dict: tapObject))
            ],
            startTime: startTime, endTime: startTime, spanId: "20",
            traceId: "30", name: "testSpan", kind: 1,
            statusCode: ["status": "ok"],
            resources: [:])
    }

    private func makeCxSpan(otel: SpanDataProtocol,
                            beforeSend: (([String: Any]) -> [String: Any]?)?) -> CxSpan? {
        let options = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp-iOS",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: [:],
            beforeSend: beforeSend,
            debug: false)
        return CxSpan(otel: otel,
                      versionMetadata: VersionMetadata(appName: "TestApp", appVersion: "1.0"),
                      sessionManager: SessionManager(),
                      networkManager: NetworkManager(),
                      viewManager: ViewManager(keyChain: KeychainManager()),
                      metricsManager: MetricsManager(),
                      options: options)
    }

    private func finalInteractionContext(of dict: [String: Any]) -> [String: Any]? {
        guard let text = dict[Keys.text.rawValue] as? [String: Any],
              let cxRum = text[Keys.cxRum.rawValue] as? [String: Any] else { return nil }
        return cxRum[Keys.interactionContext.rawValue] as? [String: Any]
    }

    func testBeforeSend_canReadIsMaskedElement() throws {
        var observedFlag: Bool?
        let cxSpan = try XCTUnwrap(makeCxSpan(otel: makeInteractionSpan(isMasked: true)) { cxRum in
            let interaction = cxRum[Keys.interactionContext.rawValue] as? [String: Any]
            observedFlag = interaction?[Keys.isMaskedElement.rawValue] as? Bool
            return cxRum
        })

        _ = cxSpan.getDictionary()

        XCTAssertEqual(observedFlag, true,
                       "beforeSend must see is_masked_element inside interaction_context")
    }

    /// The "blank the coordinates" recipe from the README, end to end.
    func testBeforeSend_canMutateInteractionContext() throws {
        let cxSpan = try XCTUnwrap(makeCxSpan(otel: makeInteractionSpan(isMasked: true)) { cxRum in
            var editable = cxRum
            if var interaction = editable[Keys.interactionContext.rawValue] as? [String: Any],
               interaction[Keys.isMaskedElement.rawValue] as? Bool == true {
                interaction[Keys.positionX.rawValue] = 0
                interaction[Keys.positionY.rawValue] = 0
                editable[Keys.interactionContext.rawValue] = interaction
            }
            return editable
        })

        let dict = try XCTUnwrap(cxSpan.getDictionary())
        let interaction = try XCTUnwrap(finalInteractionContext(of: dict))

        XCTAssertEqual(interaction[Keys.positionX.rawValue] as? Int, 0,
                       "The customer's mutation must reach the final payload")
        XCTAssertEqual(interaction[Keys.isMaskedElement.rawValue] as? Bool, true)
    }

    /// The "drop the event" recipe: returning nil discards the span.
    func testBeforeSend_canDropMaskedInteraction() throws {
        let cxSpan = try XCTUnwrap(makeCxSpan(otel: makeInteractionSpan(isMasked: true)) { cxRum in
            let interaction = cxRum[Keys.interactionContext.rawValue] as? [String: Any]
            if interaction?[Keys.isMaskedElement.rawValue] as? Bool == true { return nil }
            return cxRum
        })

        XCTAssertNil(cxSpan.getDictionary(),
                     "A dropped masked interaction must produce no payload")
    }

    /// Without beforeSend, the flag flows through to the wire payload untouched.
    func testNoBeforeSend_flagReachesPayload() throws {
        let cxSpan = try XCTUnwrap(makeCxSpan(otel: makeInteractionSpan(isMasked: false),
                                              beforeSend: nil))

        let dict = try XCTUnwrap(cxSpan.getDictionary())
        let interaction = try XCTUnwrap(finalInteractionContext(of: dict))

        XCTAssertEqual(interaction[Keys.isMaskedElement.rawValue] as? Bool, false)
    }
}
