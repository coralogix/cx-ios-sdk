//
//  DeviceContextTests.swift
//
//
//  Created by Coralogix DEV TEAM on 08/05/2024.
//

import XCTest
// 
@testable import Coralogix

final class DeviceContextTests: XCTestCase {
    var mockSpanData: SpanDataProtocol!
    
    override func setUpWithError() throws {
        mockSpanData = MockSpanData(attributes: [
            SemanticAttributes.networkConnectionType.rawValue: AttributeValue("WiFi"),
            SemanticAttributes.networkConnectionSubtype.rawValue: AttributeValue("5G")
        ])
    }
    
    override func tearDownWithError() throws {
        mockSpanData = nil
    }
    
    func testDeviceContextInitialization() {
        // Initialize DeviceContext with mock data
        let context = DeviceContext(otel: mockSpanData)
        
        // Assert that properties are initialized correctly
        XCTAssertEqual(context.networkConnectionType, "WiFi")
        XCTAssertEqual(context.networkConnectionSubtype, "5G")
    }
    
    func testDeviceContextInitializationWithMissingAttributes() {
        // Setup mock data with missing attributes
        let mockSpanData = MockSpanData(attributes: [:])
        
        // Initialize DeviceContext
        let context = DeviceContext(otel: mockSpanData)
        
        // Assert that default values are used
        XCTAssertEqual(context.networkConnectionType, "")
        XCTAssertEqual(context.networkConnectionSubtype, "")
    }
    
    func testGetDictionary() {
        let context = DeviceContext(otel: mockSpanData)
        
        // Convert to dictionary
        let dictionary = context.getDictionary()
        
        // Assert dictionary contents
        XCTAssertEqual(dictionary[Keys.networkConnectionType.rawValue] as? String, "WiFi")
        XCTAssertEqual(dictionary[Keys.networkConnectionSubtype.rawValue] as? String, "5G")
        XCTAssertEqual(dictionary[Keys.emulator.rawValue] as? Bool, true)
        XCTAssertEqual(dictionary[Keys.device.rawValue] as? String, "iPhone")
        XCTAssertEqual(dictionary[Keys.deviceName.rawValue] as? String, "iPhone15,4")
        XCTAssertEqual(dictionary[Keys.operatingSystem.rawValue] as? String, "ios")
        XCTAssertEqual(dictionary[Keys.osVersion.rawValue] as? String, "Version 17.4 (Build 21E213)")
    }
}
