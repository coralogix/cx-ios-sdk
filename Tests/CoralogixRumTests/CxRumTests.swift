//
//  CxRumTests.swift
//
//
//  Created by Coralogix DEV TEAM on 09/05/2024.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class CxRumTests: XCTestCase {
    var mockSpanData: SpanDataProtocol!
    var mockVersionMetadata: VersionMetadata!
    var mockSessionManager: SessionManager!
    var mockNetworkManager: NetworkManager!
    var mockViewerManager: ViewManager!
    var mockCxMetricsManager: MetricsManager!
    var options: CoralogixExporterOptions?
    
    override func setUpWithError() throws {
        
        let snapshot = SnapshotContext(timestamp: Date().timeIntervalSince1970,
                                       errorCount: 1,
                                       viewCount: 2,
                                       actionCount: 0,
                                       hasRecording: false)
        let dict = Helper.convertDictionary(snapshot.getDictionary())
        let snapshotString = Helper.convertDictionayToJsonString(dict: dict)
        mockSpanData = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                                 Keys.eventType.rawValue: AttributeValue("log"),
                                                 Keys.source.rawValue: AttributeValue("console"),
                                                 Keys.environment.rawValue: AttributeValue("prod"),
                                                 Keys.userId.rawValue: AttributeValue("12345"),
                                                 Keys.userName.rawValue: AttributeValue("John Doe"),
                                                 Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                                 Keys.snapshotContext.rawValue: AttributeValue(snapshotString),
                                                 Keys.screenshotId.rawValue: AttributeValue("10"),
                                                 Keys.sessionId.rawValue: AttributeValue("session_001"),
                                                 Keys.sessionCreationDate.rawValue: AttributeValue(1609459200)],
                                    startTime: Date(), spanId: "20", traceId: "30")
        mockVersionMetadata = VersionMetadata(appName: "ExampleApp", appVersion: "1.1.1")
        mockSessionManager = SessionManager()
        mockNetworkManager = NetworkManager()
        mockViewerManager = ViewManager(keyChain: KeychainManager())
        mockSessionManager.lastSnapshotEventTime = Date()
        mockCxMetricsManager = MetricsManager()
        
        let userContext = UserContext(userId: "12345", userName: "John Doe", userEmail: "john.doe@example.com", userMetadata: ["userId": "12345"])
        
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                           userContext: userContext,
                                           environment: "PROD",
                                           application: "TestApp-iOS",
                                           version: "1.0",
                                           publicKey: "token",
                                           ignoreUrls: [], //[".*\\.il$", "https://www.coralogix.com/academy"],
                                           ignoreErrors: [], //[".*errorcode=.*", "Im cusom Error"],
                                           labels: ["key": "value"],
                                           fpsSampleRate: 100,
                                           debug: true)
    }
    
    override func tearDownWithError() throws {
        mockSpanData = nil
        mockVersionMetadata = nil
        mockSessionManager = nil
        mockNetworkManager = nil
    }
    
    func testInitialization() {
        guard let options = options else { return XCTFail("Failed to load options") }
        let rumBuilder = CxRumBuilder(otel: mockSpanData,
                                      versionMetadata: mockVersionMetadata,
                                      sessionManager: mockSessionManager,
                                      viewManager: mockViewerManager,
                                      networkManager: mockNetworkManager,
                                      options: options)
        let cxRum = rumBuilder.build()
        
        // Verify build succeeded (not nil - would be nil if session attributes missing)
        XCTAssertNotNil(cxRum, "CxRum build should succeed with valid session attributes")
        guard let cxRum = cxRum else {
            XCTFail("CxRum build failed")
            return
        }
        
        // Verify initialization
        XCTAssertNotNil(cxRum.timeStamp)
        XCTAssertEqual(cxRum.environment, "prod")
        XCTAssertEqual(cxRum.mobileSDK.sdkFramework.version, Global.sdk.rawValue)
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
        guard let options = options else { return XCTFail("Failed to load options") }
        print("[CI DEBUG] Options loaded: \(options)")
        
        let rumBuilder = CxRumBuilder(otel: mockSpanData,
                                      versionMetadata: mockVersionMetadata,
                                      sessionManager: mockSessionManager,
                                      viewManager: mockViewerManager,
                                      networkManager: mockNetworkManager,
                                      options: options)
        let cxRumOptional = rumBuilder.build()
        
        XCTAssertNotNil(cxRumOptional, "CxRum build should succeed")
        guard let cxRum = cxRumOptional else {
            XCTFail("CxRum build failed")
            return
        }
        
        var payloadBuilder = CxRumPayloadBuilder(rum: cxRum, viewManager: mockViewerManager)
        let result = payloadBuilder.build()
        
        // Invoke getDictionary
        print("[CI DEBUG] The generated dictionary is: \(result as AnyObject)")
        
        // Verify each part of the dictionary
        XCTAssertNotNil(cxRum.timeStamp)
        let mobileSdkDict = result[Keys.mobileSdk.rawValue] as? [String: String]
        XCTAssertEqual(mobileSdkDict?[Keys.sdkVersion.rawValue], Global.sdk.rawValue)
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
    
    func testLastSnapshotEventTimeMoreThan60() {
        guard let options = options else { return XCTFail("Failed to load options") }
        
        mockSpanData = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                                 Keys.eventType.rawValue: AttributeValue("navigation"),
                                                 Keys.source.rawValue: AttributeValue("console"),
                                                 Keys.environment.rawValue: AttributeValue("prod"),
                                                 Keys.userId.rawValue: AttributeValue("12345"),
                                                 Keys.userName.rawValue: AttributeValue("John Doe"),
                                                 Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                                 Keys.sessionId.rawValue: AttributeValue("session_001"),
                                                 Keys.sessionCreationDate.rawValue: AttributeValue(1609459200)],
                                    startTime: Date(), spanId: "20", traceId: "30")
        
        let oneMinuteInThePast: TimeInterval = -120
        
        // Get the current date and time
        let currentDate = Date()
        
        // Calculate the date and time 1 minute in the past
        let pastDate = currentDate.addingTimeInterval(oneMinuteInThePast)
        
        mockSessionManager.lastSnapshotEventTime = pastDate
        let rumBuilder = CxRumBuilder(otel: mockSpanData,
                                      versionMetadata: mockVersionMetadata,
                                      sessionManager: mockSessionManager,
                                      viewManager: mockViewerManager,
                                      networkManager: mockNetworkManager,
                                      options: options)
        let cxRumOptional = rumBuilder.build()
        
        XCTAssertNotNil(cxRumOptional, "CxRum build should succeed")
        guard let cxRum = cxRumOptional else {
            XCTFail("CxRum build failed")
            return
        }
        
        XCTAssertNotNil(cxRum.snapshotContext)
    }
}
