//
//  SessionContextTests.swift
//  
//
//  Created by Coralogix DEV TEAM on 06/05/2024.
//

import Foundation
import XCTest
import OpenTelemetrySdk
import OpenTelemetryApi
@testable import CoralogixRum

final class SessionContextTests: XCTestCase {
    
    // Mock classes or structures if necessary
    var mockSpanData: SpanDataProtocol!
    var versionMetadata: VersionMetadata!
    var sessionMetadata: SessionMetadata!
    
    override func setUpWithError() throws {
        // Initialize your mock objects here
        mockSpanData = MockSpanData(attributes: [Keys.userId.rawValue: AttributeValue("12345"),
                                                 Keys.userName.rawValue: AttributeValue("John Doe"),
                                                 Keys.userEmail.rawValue: AttributeValue("john.doe@example.com")])
        
        sessionMetadata = SessionMetadata(sessionId: "session_001",
                                          sessionCreationDate: TimeInterval(1609459200))
        versionMetadata = VersionMetadata(appName: "test-app", appVersion: "1.1.1")
    }

    override func tearDownWithError() throws {
        sessionMetadata = nil
        versionMetadata = nil
        mockSpanData = nil
    }
    
    func testInitSessionContext() {
        let context = SessionContext(otel: mockSpanData,
                                     versionMetadata: versionMetadata,
                                     sessionMetadata: sessionMetadata,
                                     userMetadata: ["role": "admin"])
        
        XCTAssertEqual(context.sessionId, "session_001")
        XCTAssertEqual(context.sessionCreationDate, 1609459200)
        XCTAssertEqual(context.operatingSystem, Global.getOs())
        XCTAssertEqual(context.osVersion, Global.osVersionInfo())
        XCTAssertEqual(context.device, Global.getDeviceModel())
        XCTAssertEqual(context.userId, "12345")
        XCTAssertEqual(context.userName, "John Doe")
        XCTAssertEqual(context.userEmail, "john.doe@example.com")
        XCTAssertEqual(context.userMetadata?["role"], "admin")
    }

    func testGetDictionary() {
        let context = SessionContext(otel: mockSpanData,
                                     versionMetadata: versionMetadata,
                                     sessionMetadata: sessionMetadata,
                                     userMetadata: ["role": "admin"])
        let dictionary = context.getDictionary()
        
        XCTAssertEqual(dictionary[Keys.sessionId.rawValue] as? String, "session_001")
        XCTAssertEqual(dictionary[Keys.sessionCreationDate.rawValue] as? Int, 1609459200.milliseconds)
        XCTAssertEqual(dictionary[Keys.operatingSystem.rawValue] as? String, Global.getOs())
        XCTAssertEqual(dictionary[Keys.osVersion.rawValue] as? String, Global.osVersionInfo())
        XCTAssertEqual(dictionary[Keys.device.rawValue] as? String, Global.getDeviceModel())
        XCTAssertEqual(dictionary[Keys.userId.rawValue] as? String, "12345")
        XCTAssertEqual(dictionary[Keys.userName.rawValue] as? String, "John Doe")
        XCTAssertEqual(dictionary[Keys.userEmail.rawValue] as? String, "john.doe@example.com")
        XCTAssertEqual(dictionary[Keys.userMetadata.rawValue] as? [String: String], ["role": "admin"])
    }

    func testGetPrevSessionDictionary() {
        let context = SessionContext(otel: mockSpanData, versionMetadata: versionMetadata, sessionMetadata: sessionMetadata, userMetadata: nil)
        let prevDictionary = context.getPrevSessionDictionary()
        
        XCTAssertEqual(prevDictionary[Keys.sessionId.rawValue] as? String, "session_001")
        XCTAssertEqual(prevDictionary[Keys.sessionCreationDate.rawValue] as? Int, 1609459200.milliseconds)
    }
}


