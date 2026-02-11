//
//  SessionContextTests.swift
//  
//
//  Created by Coralogix DEV TEAM on 06/05/2024.
//

import Foundation
import XCTest
import CoralogixInternal
@testable import Coralogix

final class SessionContextTests: XCTestCase {
    // Mock classes or structures if necessary
    var mockSpanData: SpanDataProtocol!
    var versionMetadata: VersionMetadata!
    var sessionMetadata: SessionMetadata!
    
    override func setUpWithError() throws {
        // Initialize your mock objects here
        mockSpanData = MockSpanData(attributes: [Keys.userId.rawValue: AttributeValue("12345"),
                                                 Keys.userName.rawValue: AttributeValue("John Doe"),
                                                 Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                                 Keys.sessionId.rawValue: AttributeValue("session_001"),
                                                 Keys.sessionCreationDate.rawValue: AttributeValue("1609459200")
                                                ])
        sessionMetadata = SessionMetadata(sessionId: "session_001",
                                          sessionCreationDate: TimeInterval(1609459200),
                                          using: MockKeyschainManager())
        versionMetadata = VersionMetadata(appName: "test-app", appVersion: "1.1.1")
    }

    override func tearDownWithError() throws {
        sessionMetadata = nil
        versionMetadata = nil
        mockSpanData = nil
    }
    
    func testInitSessionContext() {
        let contextOptional = SessionContext(otel: mockSpanData,
                                            userMetadata: ["role": "admin"])
        
        XCTAssertNotNil(contextOptional, "SessionContext should succeed with valid session attributes")
        guard let context = contextOptional else {
            XCTFail("SessionContext init failed")
            return
        }
        
        XCTAssertEqual(context.sessionId, "session_001")
        XCTAssertEqual(context.sessionCreationDate, 1609459200)
        XCTAssertEqual(context.userId, "12345")
        XCTAssertEqual(context.userName, "John Doe")
        XCTAssertEqual(context.userEmail, "john.doe@example.com")
        XCTAssertEqual(context.userMetadata?["role"], "admin")
        XCTAssertFalse(context.hasRecording)
    }

    func testGetDictionary() {
        guard let context = SessionContext(otel: mockSpanData,
                                          userMetadata: ["role": "admin"]) else {
            XCTFail("SessionContext init failed")
            return
        }
        let dictionary = context.getDictionary()
        
        XCTAssertEqual(dictionary[Keys.sessionId.rawValue] as? String, "session_001")
        XCTAssertEqual(dictionary[Keys.sessionCreationDate.rawValue] as? Int, 1609459200.milliseconds)
        XCTAssertEqual(dictionary[Keys.userId.rawValue] as? String, "12345")
        XCTAssertEqual(dictionary[Keys.userName.rawValue] as? String, "John Doe")
        XCTAssertEqual(dictionary[Keys.userEmail.rawValue] as? String, "john.doe@example.com")
        XCTAssertEqual(dictionary[Keys.userMetadata.rawValue] as? [String: String], ["role": "admin"])
        XCTAssertEqual(dictionary[Keys.hasRecording.rawValue] as? Bool, false)
    }

    func testHasSessionReplay() {
        guard let context = SessionContext(otel: mockSpanData,
                                          userMetadata: ["role": "admin"],
                                          hasRecording: true) else {
            XCTFail("SessionContext init failed")
            return
        }
        let dictionary = context.getDictionary()
        XCTAssertEqual(dictionary[Keys.hasRecording.rawValue] as? Bool, true)
    }

    func testGetPrevSessionDictionary() {
        guard let context = SessionContext(otel: mockSpanData, userMetadata: nil) else {
            XCTFail("SessionContext init failed")
            return
        }
        let prevDictionary = context.getPrevSessionDictionary()
        
        XCTAssertEqual(prevDictionary[Keys.sessionId.rawValue] as? String, "session_001")
        XCTAssertEqual(prevDictionary[Keys.sessionCreationDate.rawValue] as? Int, 1609459200.milliseconds)
    }
    
    func testResetSessionMetaDataDictionary() {
        XCTAssertNotNil(sessionMetadata)
        sessionMetadata.resetSessionMetadata()
        XCTAssertEqual(sessionMetadata.sessionId, "")
        XCTAssertEqual(sessionMetadata.sessionCreationDate, 0)
    }
}


