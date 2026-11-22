//
//  DeepCopyTests.swift
//  Coralogix
//

import XCTest
@testable import Coralogix

final class DeepCopyTests: XCTestCase {

    func test_deepCopy_mutatingNestedContainerInCopy_leavesOriginalUnchanged() throws {
        let labels = NSMutableDictionary(dictionary: ["a": "1"])
        let original: [[String: Any]] = [["cx_rum": ["labels": labels]]]

        let copy = original.deepCopy()
        let cxRum = try XCTUnwrap(copy[0]["cx_rum"] as? [String: Any])
        let copiedLabels = try XCTUnwrap(cxRum["labels"])
        (copiedLabels as AnyObject as? NSMutableDictionary)?["a"] = "changed"

        XCTAssertEqual(labels["a"] as? String, "1")
    }

    func test_deepCopy_detachesNestedFoundationMutableContainers() throws {
        let sharedLabels = NSMutableDictionary(dictionary: ["a": "1"])
        let sharedTags = NSMutableArray(array: ["x"])
        let original: [[String: Any]] = [
            ["cx_rum": ["labels": sharedLabels, "items": [sharedTags]]]
        ]

        let copy = original.deepCopy()
        sharedLabels["a"] = "changed"
        sharedTags.add("y")

        let cxRum = try XCTUnwrap(copy[0]["cx_rum"] as? [String: Any])
        XCTAssertEqual(cxRum["labels"] as? [String: String], ["a": "1"])
        let items = try XCTUnwrap(cxRum["items"] as? [[String]])
        XCTAssertEqual(items, [["x"]])
    }

    func test_deepCopy_preservesValues() throws {
        let original: [[String: Any]] = [
            ["s": "v", "i": 1, "d": 2.5, "b": true, "nested": ["list": [1, ["k": "v"]]]]
        ]

        let copy = original.deepCopy()

        XCTAssertTrue(NSArray(array: copy).isEqual(to: original))
    }
}
