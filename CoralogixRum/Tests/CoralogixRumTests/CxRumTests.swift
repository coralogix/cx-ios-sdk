//
//  CxRumTests.swift
//
//
//  Created by Coralogix DEV TEAM on 09/05/2024.
//

import XCTest
import OpenTelemetrySdk
import OpenTelemetryApi

@testable import CoralogixRum

final class CxRumTests: XCTestCase {
    var mockSpanData: SpanDataProtocol!
    var mockVersionMetadata: VersionMetadata!
    var mockSessionManager: SessionManager!
    var mockNetworkManager: NetworkManager!
    
    override func setUpWithError() throws {
        mockSpanData = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                                 Keys.eventType.rawValue: AttributeValue("log"),
                                                 Keys.source.rawValue: AttributeValue("console"),
                                                 Keys.environment.rawValue: AttributeValue("prod"),
                                                 Keys.userId.rawValue: AttributeValue("12345"),
                                                 Keys.userName.rawValue: AttributeValue("John Doe"),
                                                 Keys.userEmail.rawValue: AttributeValue("john.doe@example.com")],
                                    startTime: Date(), spanId: "20", traceId: "30")
        mockVersionMetadata = VersionMetadata(appName: "ExampleApp", appVersion: "1.1.1")
        mockSessionManager = SessionManager()
        mockNetworkManager = NetworkManager()
    }
    
    override func tearDownWithError() throws {
        mockSpanData = nil
        mockVersionMetadata = nil
        mockSessionManager = nil
        mockNetworkManager = nil
    }
    
    func testInitialization() {
        let cxRum = CxRum(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            networkManager: mockNetworkManager,
            userMetadata: ["userId": "12345"],
            labels: ["key": "value"]
        )
        
        // Verify initialization
        XCTAssertNotNil(cxRum.timeStamp)
        XCTAssertEqual(cxRum.environment, "prod")
        XCTAssertEqual(cxRum.mobileSdk, Global.iosSdk.rawValue)
        XCTAssertEqual(cxRum.versionMetadata.appName, "ExampleApp")
        XCTAssertEqual(cxRum.traceId, "30")
        XCTAssertEqual(cxRum.spanId, "20")
        XCTAssertNotNil(cxRum.sessionContext)
        XCTAssertNotNil(cxRum.errorContext)
        XCTAssertNotNil(cxRum.deviceContext)
        XCTAssertNil(cxRum.prevSessionContext)
        XCTAssertEqual(cxRum.labels as? [String: String], ["key": "value"])
    }
    
    func testGetDictionary() {
        let cxRum = CxRum(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            networkManager: mockNetworkManager,
            userMetadata: ["userId": "12345"],
            labels: ["key": "value"]
        )
        
        // Invoke getDictionary
        let result = cxRum.getDictionary()
        
        // Verify each part of the dictionary
        XCTAssertNotNil(cxRum.timeStamp)
        let mobileSdkDict = result[Keys.mobileSdk.rawValue] as? [String: String]
        XCTAssertEqual(mobileSdkDict?[Keys.sdkVersion.rawValue], "1.0.0")  // Assuming "CurrentSDKVersion" is a placeholder
        XCTAssertEqual(mobileSdkDict?[Keys.framework.rawValue], "swift")
        XCTAssertEqual(mobileSdkDict?[Keys.operatingSystem.rawValue], "ios")
        
        XCTAssertEqual(result[Keys.versionMetaData.rawValue] as? [String: String],
                       [Keys.appName.rawValue: "ExampleApp",
                        Keys.appVersion.rawValue: "1.1.1"])
        
        // Ensure correct dictionary structures for context-related keys
        XCTAssertNotNil(result[Keys.sessionContext.rawValue])
        XCTAssertNotNil(result[Keys.eventContext.rawValue])
        XCTAssertEqual(result[Keys.environment.rawValue] as? String, "prod")  // Assuming the environment
        
        XCTAssertEqual(result[Keys.traceId.rawValue] as? String, "30")
        XCTAssertEqual(result[Keys.spanId.rawValue] as? String, "20")
        XCTAssertEqual(result[Keys.platform.rawValue] as? String, "mobile")
        
        XCTAssertNotNil(result[Keys.deviceState.rawValue])
        
        if let logContext = result[Keys.logContext.rawValue] as? [String: Any] {
            XCTAssertEqual(logContext[Keys.message.rawValue] as? String, "")
        }
    }
}
