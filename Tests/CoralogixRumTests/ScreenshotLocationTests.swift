//
//  ScreenshotLocationTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 09/07/2025.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class ScreenshotLocationTests: XCTestCase {
    
    func testToProperties_returnsExpectedDictionary() {
        // Given
        let location = ScreenshotLocation(segmentIndex: 2, page: 5, screenshotId: "abc123")
        
        // When
        let props = location.toProperties()
        
        // Then
        XCTAssertEqual(props[Keys.segmentIndex.rawValue] as? Int, 2)
        XCTAssertEqual(props[Keys.page.rawValue] as? Int, 5)
        XCTAssertEqual(props[Keys.screenshotId.rawValue] as? String, "abc123")
    }
    
    func testToProperties_containsAllKeys() {
        let location = ScreenshotLocation(segmentIndex: 1, page: 1, screenshotId: "id_001")
        let props = location.toProperties()
        
        XCTAssertTrue(props.keys.contains(Keys.segmentIndex.rawValue))
        XCTAssertTrue(props.keys.contains(Keys.page.rawValue))
        XCTAssertTrue(props.keys.contains(Keys.screenshotId.rawValue))
    }
    
    func testToPropertiesReturnsCorrectDictionary() {
        // Arrange
        let screenshotLocation = ScreenshotLocation(
            segmentIndex: 3,
            page: 5,
            screenshotId: "abc123"
        )
        
        // Act
        let properties = screenshotLocation.toProperties()
        
        // Assert
        XCTAssertEqual(properties[Keys.screenshotId.rawValue] as? String, "abc123")
        XCTAssertEqual(properties[Keys.page.rawValue] as? Int, 5)
        XCTAssertEqual(properties[Keys.segmentIndex.rawValue] as? Int, 3)
    }
}
