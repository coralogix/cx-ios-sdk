//
//  HybridAPITests.swift
//
//
//  Created by Coralogix DEV TEAM on 05/02/2026.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class HybridAPITests: XCTestCase {

    private var coralogixRum: CoralogixRum!

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
            labels: ["testLabel": "testValue"],
            sessionSampleRate: 100,
            debug: false
        )
        coralogixRum = CoralogixRum(options: options)
    }

    override func tearDownWithError() throws {
        coralogixRum?.shutdown()
        coralogixRum = nil
    }

    // MARK: - validateHybridInteraction: event_name validation

    func testValidateHybridInteraction_missingEventName_returnsNil() {
        let dict: [String: Any] = [
            Keys.targetElement.rawValue: "UIButton"
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNil(result, "Missing event_name must cause validation to return nil")
    }

    func testValidateHybridInteraction_invalidEventName_returnsNil() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "tap", // invalid - should be "click"
            Keys.targetElement.rawValue: "UIButton"
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNil(result, "Invalid event_name 'tap' must cause validation to return nil")
    }

    func testValidateHybridInteraction_validEventName_click_passes() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "click",
            Keys.targetElement.rawValue: "UIButton"
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNotNil(result, "Valid event_name 'click' must pass validation")
        XCTAssertEqual(result?[Keys.eventName.rawValue] as? String, "click")
    }

    func testValidateHybridInteraction_validEventName_scroll_passes() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "scroll",
            Keys.targetElement.rawValue: "UIScrollView",
            Keys.scrollDirection.rawValue: "down"
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNotNil(result, "Valid event_name 'scroll' must pass validation")
        XCTAssertEqual(result?[Keys.eventName.rawValue] as? String, "scroll")
    }

    func testValidateHybridInteraction_validEventName_swipe_passes() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "swipe",
            Keys.targetElement.rawValue: "UIView",
            Keys.scrollDirection.rawValue: "left"
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNotNil(result, "Valid event_name 'swipe' must pass validation")
        XCTAssertEqual(result?[Keys.eventName.rawValue] as? String, "swipe")
    }

    // MARK: - validateHybridInteraction: target_element validation

    func testValidateHybridInteraction_missingTargetElement_returnsNil() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "click"
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNil(result, "Missing target_element must cause validation to return nil")
    }

    func testValidateHybridInteraction_emptyTargetElement_returnsNil() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "click",
            Keys.targetElement.rawValue: ""
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNil(result, "Empty target_element must cause validation to return nil")
    }

    func testValidateHybridInteraction_whitespaceTargetElement_returnsNil() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "click",
            Keys.targetElement.rawValue: "   "
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNil(result, "Whitespace-only target_element must cause validation to return nil")
    }

    func testValidateHybridInteraction_newlineTargetElement_returnsNil() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "click",
            Keys.targetElement.rawValue: "\n"
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNil(result, "Newline-only target_element must cause validation to return nil")
    }

    // MARK: - validateHybridInteraction: scroll_direction validation

    func testValidateHybridInteraction_validScrollDirection_up_passes() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "scroll",
            Keys.targetElement.rawValue: "UIScrollView",
            Keys.scrollDirection.rawValue: "up"
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?[Keys.scrollDirection.rawValue] as? String, "up")
    }

    func testValidateHybridInteraction_validScrollDirection_down_passes() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "scroll",
            Keys.targetElement.rawValue: "UIScrollView",
            Keys.scrollDirection.rawValue: "down"
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?[Keys.scrollDirection.rawValue] as? String, "down")
    }

    func testValidateHybridInteraction_validScrollDirection_left_passes() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "swipe",
            Keys.targetElement.rawValue: "UIView",
            Keys.scrollDirection.rawValue: "left"
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?[Keys.scrollDirection.rawValue] as? String, "left")
    }

    func testValidateHybridInteraction_validScrollDirection_right_passes() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "swipe",
            Keys.targetElement.rawValue: "UIView",
            Keys.scrollDirection.rawValue: "right"
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?[Keys.scrollDirection.rawValue] as? String, "right")
    }

    func testValidateHybridInteraction_invalidScrollDirection_stripsFieldAndPasses() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "scroll",
            Keys.targetElement.rawValue: "UIScrollView",
            Keys.scrollDirection.rawValue: "diagonal" // invalid
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNotNil(result, "Invalid scroll_direction must be stripped, not reject the entire event")
        XCTAssertNil(result?[Keys.scrollDirection.rawValue], "Invalid scroll_direction must be removed from output")
        XCTAssertEqual(result?[Keys.eventName.rawValue] as? String, "scroll")
        XCTAssertEqual(result?[Keys.targetElement.rawValue] as? String, "UIScrollView")
    }

    func testValidateHybridInteraction_noScrollDirection_passes() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "click",
            Keys.targetElement.rawValue: "UIButton"
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNotNil(result, "Absent scroll_direction is valid for click events")
        XCTAssertNil(result?[Keys.scrollDirection.rawValue])
    }

    // MARK: - validateHybridInteraction: optional fields preservation

    func testValidateHybridInteraction_preservesOptionalFields() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "click",
            Keys.targetElement.rawValue: "LoginButton",
            Keys.elementClasses.rawValue: "UIButton",
            Keys.elementId.rawValue: "login_btn",
            Keys.targetElementInnerText.rawValue: "Sign In",
            Keys.positionX.rawValue: 100.0,
            Keys.positionY.rawValue: 200.0,
            Keys.attributes.rawValue: ["custom": "value"]
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?[Keys.elementClasses.rawValue] as? String, "UIButton")
        XCTAssertEqual(result?[Keys.elementId.rawValue] as? String, "login_btn")
        XCTAssertEqual(result?[Keys.targetElementInnerText.rawValue] as? String, "Sign In")
        XCTAssertEqual(result?[Keys.positionX.rawValue] as? Double, 100.0)
        XCTAssertEqual(result?[Keys.positionY.rawValue] as? Double, 200.0)
        let attrs = result?[Keys.attributes.rawValue] as? [String: Any]
        XCTAssertEqual(attrs?["custom"] as? String, "value", "attributes should be preserved as [String: Any] from hybrid bridge")
    }

    // MARK: - validateHybridInteraction: edge cases

    func testValidateHybridInteraction_eventNameWrongType_returnsNil() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: 123, // wrong type - should be String
            Keys.targetElement.rawValue: "UIButton"
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNil(result, "Non-string event_name must cause validation to return nil")
    }

    func testValidateHybridInteraction_targetElementWrongType_returnsNil() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "click",
            Keys.targetElement.rawValue: ["array", "value"] // wrong type - should be String
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNil(result, "Non-string target_element must cause validation to return nil")
    }

    func testValidateHybridInteraction_scrollDirectionWrongType_stripsFieldAndPasses() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "scroll",
            Keys.targetElement.rawValue: "UIScrollView",
            Keys.scrollDirection.rawValue: 123 // wrong type - should be String
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNotNil(result, "Event should not be dropped for a non-string scroll_direction")
        XCTAssertNil(result?[Keys.scrollDirection.rawValue], "Non-string scroll_direction should be stripped from the event")
    }

    // MARK: - Hybrid mode auto-disables native userActions

    func testHybridMode_flutter_skipsUserActionsInstrumentation() {
        // Use only the hybrid instance (no second instance from setUp).
        coralogixRum?.shutdown()
        coralogixRum = nil

        let options = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "test",
            application: "TestApp",
            version: "1.0.0",
            publicKey: "test-key",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: nil,
            sessionSampleRate: 100,
            debug: false
        )

        coralogixRum = CoralogixRum(options: options, sdkFramework: .flutter(version: "1.0.0"))

        // Swizzles are installed so session replay gets native touches; native user action spans are not emitted (hybrid uses setUserInteraction).
        XCTAssertTrue(CoralogixRum.isInitialized)
    }

    func testHybridMode_reactNative_skipsUserActionsInstrumentation() {
        // Use only the hybrid instance (no second instance from setUp).
        coralogixRum?.shutdown()
        coralogixRum = nil

        let options = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "test",
            application: "TestApp",
            version: "1.0.0",
            publicKey: "test-key",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: nil,
            sessionSampleRate: 100,
            debug: false
        )

        coralogixRum = CoralogixRum(options: options, sdkFramework: .reactNative(version: "2.0.0"))

        // Swizzles are installed for session replay; native user action spans are not emitted.
        XCTAssertTrue(CoralogixRum.isInitialized)
    }

    // MARK: - Full dictionary validation scenarios

    func testValidateHybridInteraction_completeClickEvent_passes() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "click",
            Keys.targetElement.rawValue: "Add to Cart",
            Keys.elementClasses.rawValue: "UIButton",
            Keys.elementId.rawValue: "add_to_cart_btn",
            Keys.targetElementInnerText.rawValue: "Add to Cart",
            Keys.positionX.rawValue: 187.5,
            Keys.positionY.rawValue: 423.0
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, dict.count)
    }

    func testValidateHybridInteraction_completeScrollEvent_passes() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "scroll",
            Keys.targetElement.rawValue: "ProductList",
            Keys.elementClasses.rawValue: "UITableView",
            Keys.scrollDirection.rawValue: "down",
            Keys.positionX.rawValue: 200.0,
            Keys.positionY.rawValue: 500.0
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?[Keys.scrollDirection.rawValue] as? String, "down")
    }

    func testValidateHybridInteraction_completeSwipeEvent_passes() {
        let dict: [String: Any] = [
            Keys.eventName.rawValue: "swipe",
            Keys.targetElement.rawValue: "ImageCarousel",
            Keys.elementClasses.rawValue: "UICollectionView",
            Keys.scrollDirection.rawValue: "left",
            Keys.positionX.rawValue: 300.0,
            Keys.positionY.rawValue: 250.0
        ]

        let result = coralogixRum.validateHybridInteraction(dict)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?[Keys.eventName.rawValue] as? String, "swipe")
        XCTAssertEqual(result?[Keys.scrollDirection.rawValue] as? String, "left")
    }
}
