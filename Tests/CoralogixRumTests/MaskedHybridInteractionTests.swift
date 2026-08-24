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
/// so masking here resolves from the payload's coordinates against the deliberate-masking
/// geometry (`cxMask` only — not the replay's pixel policy), or from the wrapper's own
/// `is_masked` verdict.
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

    // MARK: - The replay's pixel policy is not an input to the verdict

    /// A window carrying both kinds of masked content: a `cxMask` view (deliberate masking) and
    /// a label the replay's `maskText` policy would black out. Returns the geometry each of the
    /// two consumers collects — the capture pass takes the policy, the interaction path does not.
    private func makeMixedMaskingWindow() -> (window: UIWindow,
                                              policyLabel: UILabel,
                                              deliberatePoint: CGPoint,
                                              interactionRects: [CGRect],
                                              captureRects: [CGRect]) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.isHidden = false  // windows are born hidden; the walk skips hidden views

        let deliberate = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        deliberate.cxMask = true
        let policyLabel = UILabel(frame: CGRect(x: 0, y: 200, width: 100, height: 40))
        policyLabel.text = "secret code"
        window.addSubview(deliberate)
        window.addSubview(policyLabel)

        return (window: window,   // retained: subviews are released when the window goes
                policyLabel: policyLabel,
                deliberatePoint: CGPoint(x: 50, y: 50),
                // The inputs `UIView.deliberateMaskRects()` uses: policy off.
                interactionRects: window.collectNativeMaskRects(in: window,
                                                                maskText: nil,
                                                                maskAllImages: false),
                // The inputs the capture pass uses, and so the replay's tap-marker test.
                captureRects: window.collectNativeMaskRects(in: window,
                                                            maskText: ["secret"],
                                                            maskAllImages: true))
    }

    /// The acceptance pin. With `maskText` configured and no `cxMask` on the element, a tap on
    /// text reports unmasked and ships its real text — on both paths. The pixel policy answers
    /// whether pixels are hidden in a frame, not whether text may leave the device, and letting
    /// it decide the verdict over-masks every text tap on a wrapper's defaults. Android and
    /// Flutter resolve from deliberate masking alone; this is iOS matching them.
    func testPolicyMaskedText_reportsUnmasked_withRealText_bothPaths() throws {
        let fixture = makeMixedMaskingWindow()
        let point = CGPoint(x: 50, y: 220)

        XCTAssertTrue(fixture.captureRects.contains { $0.contains(point) },
                      "Fixture check: the capture pass must mask these pixels, so this test is "
                      + "about the two consumers diverging — not about nothing being masked")
        XCTAssertFalse(fixture.interactionRects.contains { $0.contains(point) },
                       "The interaction path's geometry must not contain the policy-masked label")

        let native = TapDataExtractor.extract(
            from: TouchEvent(view: fixture.policyLabel, location: point,
                             eventType: .click, scrollDirection: nil),
            maskRects: fixture.interactionRects)

        let hybrid = try XCTUnwrap(coralogixRum.validateHybridInteraction(
            clickPayload(x: point.x, y: point.y,
                         extra: [Keys.targetElementInnerText.rawValue: "secret code"]),
            maskRects: fixture.interactionRects))

        XCTAssertEqual(native[Keys.isMaskedElement.rawValue] as? Bool, false)
        XCTAssertEqual(native[Keys.targetElementInnerText.rawValue] as? String, "secret code")
        XCTAssertEqual(hybrid[Keys.isMaskedElement.rawValue] as? Bool, false)
        XCTAssertEqual(hybrid[Keys.targetElementInnerText.rawValue] as? String, "secret code")
    }

    /// Deliberate masking is untouched: a tap on a `cxMask` view still reports masked with `***`.
    func testDeliberatelyMaskedView_stillReportsMasked_bothPaths() throws {
        let fixture = makeMixedMaskingWindow()
        let point = fixture.deliberatePoint

        let button = UIButton()
        button.setTitle("7", for: .normal)
        let native = TapDataExtractor.extract(
            from: TouchEvent(view: button, location: point, eventType: .click, scrollDirection: nil),
            maskRects: fixture.interactionRects)

        let hybrid = try XCTUnwrap(coralogixRum.validateHybridInteraction(
            clickPayload(x: point.x, y: point.y), maskRects: fixture.interactionRects))

        XCTAssertEqual(native[Keys.isMaskedElement.rawValue] as? Bool, true)
        XCTAssertEqual(native[Keys.targetElementInnerText.rawValue] as? String, "***")
        XCTAssertEqual(hybrid[Keys.isMaskedElement.rawValue] as? Bool, true)
        XCTAssertEqual(hybrid[Keys.targetElementInnerText.rawValue] as? String, "***")
    }

    /// Masking is inherited, so an unmasked key inside a `cxMask` container is still masked —
    /// on the native path via the view-tree walk, which needs no geometry at all.
    func testUnmaskedKeyInsideMaskedContainer_stillReportsMasked() {
        let keypad = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 160))
        keypad.cxMask = true
        let key = UIButton(frame: CGRect(x: 10, y: 10, width: 50, height: 40))
        key.setTitle("7", for: .normal)
        keypad.addSubview(key)

        let native = TapDataExtractor.extract(
            from: TouchEvent(view: key, location: CGPoint(x: 35, y: 30),
                             eventType: .click, scrollDirection: nil),
            maskRects: nil)

        XCTAssertEqual(native[Keys.isMaskedElement.rawValue] as? Bool, true)
        XCTAssertEqual(native[Keys.targetElementInnerText.rawValue] as? String, "***")
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
            // Coordinates travel to the wire inside interaction_context.attributes.
            Keys.attributes.rawValue: [Keys.positionX.rawValue: 50.0,
                                       Keys.positionY.rawValue: 50.0]
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

    /// The "blank the coordinates" recipe from the README, end to end: coordinates are
    /// serialised from the nested attributes map, so that is what the callback must edit.
    func testBeforeSend_canMutateInteractionContext() throws {
        let cxSpan = try XCTUnwrap(makeCxSpan(otel: makeInteractionSpan(isMasked: true)) { cxRum in
            var editable = cxRum
            if var interaction = editable[Keys.interactionContext.rawValue] as? [String: Any],
               interaction[Keys.isMaskedElement.rawValue] as? Bool == true {
                var attributes = interaction[Keys.attributes.rawValue] as? [String: Any] ?? [:]
                attributes[Keys.positionX.rawValue] = 0
                attributes[Keys.positionY.rawValue] = 0
                interaction[Keys.attributes.rawValue] = attributes
                editable[Keys.interactionContext.rawValue] = interaction
            }
            return editable
        })

        let dict = try XCTUnwrap(cxSpan.getDictionary())
        let interaction = try XCTUnwrap(finalInteractionContext(of: dict))
        let attributes = try XCTUnwrap(interaction[Keys.attributes.rawValue] as? [String: Any])

        XCTAssertEqual(attributes[Keys.positionX.rawValue] as? Int, 0,
                       "The customer's mutation must reach the transmitted attributes map")
        XCTAssertEqual(attributes[Keys.positionY.rawValue] as? Int, 0)
        XCTAssertEqual(interaction[Keys.isMaskedElement.rawValue] as? Bool, true)
    }

    /// The flag is a visible read-only field: callbacks key their policy on it, but the SDK's
    /// observation is restored after the merge so the record of what was masked cannot be
    /// forged — same treatment as `session_context.isSessionSampledIn`.
    func testBeforeSend_cannotForgeIsMaskedElement() throws {
        let cxSpan = try XCTUnwrap(makeCxSpan(otel: makeInteractionSpan(isMasked: true)) { cxRum in
            var editable = cxRum
            var interaction = editable[Keys.interactionContext.rawValue] as? [String: Any] ?? [:]
            interaction[Keys.isMaskedElement.rawValue] = false
            var attributes = interaction[Keys.attributes.rawValue] as? [String: Any] ?? [:]
            attributes[Keys.positionX.rawValue] = 0
            interaction[Keys.attributes.rawValue] = attributes
            editable[Keys.interactionContext.rawValue] = interaction
            return editable
        })

        let dict = try XCTUnwrap(cxSpan.getDictionary())
        let interaction = try XCTUnwrap(finalInteractionContext(of: dict))
        let attributes = try XCTUnwrap(interaction[Keys.attributes.rawValue] as? [String: Any])

        XCTAssertEqual(interaction[Keys.isMaskedElement.rawValue] as? Bool, true,
                       "A callback that rewrites the flag must not survive the restore")
        XCTAssertEqual(attributes[Keys.positionX.rawValue] as? Int, 0,
                       "Permitted mutations alongside the forged flag must still apply")
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
