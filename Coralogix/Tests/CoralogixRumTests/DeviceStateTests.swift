//
//  DeviceStateTests.swift
//  
//
//  Created by Coralogix DEV TEAM on 12/05/2024.
//

import XCTest
// import OpenTelemetryApi
@testable import Coralogix

final class DeviceStateTests: XCTestCase {
    var mockNetworkManager: MockNetworkManager!
    
    override func setUpWithError() throws {
        mockNetworkManager = MockNetworkManager()
    }

    override func tearDownWithError() throws {
        mockNetworkManager = nil
    }
    
    func testDeviceStateInitialization() {
        // Initialize DeviceContext with mock data
        let context = DeviceState(networkManager: mockNetworkManager)
        
        // Assert that properties are initialized correctly
        XCTAssertEqual(context.battery, "-1.0")
        XCTAssertEqual(context.networkType, "5G")
    }
    
    func testGetDictionary() {
        let context = DeviceState(networkManager: mockNetworkManager)
        
        // Convert to dictionary
        let dictionary = context.getDictionary()
        
        // Assert dictionary contents
        XCTAssertEqual(dictionary[Keys.networkType.rawValue] as? String, "5G")
        XCTAssertEqual(dictionary[Keys.battery.rawValue] as? String, "-1.0")
    }
}
