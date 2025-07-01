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
    
    override func setUpWithError() throws {
        
        let snapshot = SnapshotContext(timestamp: Date().timeIntervalSince1970,
                                       errorCount: 1,
                                       viewCount: 2,
                                       clickCount: 0,
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
                                                 Keys.screenshotId.rawValue: AttributeValue("10")],
                                    startTime: Date(), spanId: "20", traceId: "30")
        mockVersionMetadata = VersionMetadata(appName: "ExampleApp", appVersion: "1.1.1")
        mockSessionManager = SessionManager()
        mockNetworkManager = NetworkManager()
        mockViewerManager = ViewManager(keyChain: KeychainManager())
        mockSessionManager.lastSnapshotEventTime = Date()
        mockCxMetricsManager = MetricsManager()
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
            viewManager: mockViewerManager,
            networkManager: mockNetworkManager,
            metricsManager: mockCxMetricsManager,
            userMetadata: ["userId": "12345"],
            labels: ["key": "value"]
        )
        
        // Verify initialization
        XCTAssertNotNil(cxRum.timeStamp)
        XCTAssertEqual(cxRum.environment, "prod")
        XCTAssertEqual(cxRum.mobileSdk, Global.sdk.rawValue)
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
        var cxRum = CxRum(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            viewManager: mockViewerManager,
            networkManager: mockNetworkManager,
            metricsManager: mockCxMetricsManager,
            userMetadata: ["userId": "12345"],
            labels: ["key": "value"]
        )
        
        // Invoke getDictionary
        let result = cxRum.getDictionary()
        
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
    
    func testGetDictionaryOneMinuteFromLastPassSnapshot() {
        var cxRum = CxRum(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            viewManager: mockViewerManager,
            networkManager: mockNetworkManager,
            metricsManager: mockCxMetricsManager,
            userMetadata: ["userId": "12345"],
            labels: ["key": "value"]
        )
        
        let currentTime = Date()
        cxRum.isOneMinuteFromLastSnapshotPass = true
        cxRum.snapshotContext = SnapshotContext(timestamp: currentTime.timeIntervalSince1970,
                                                errorCount: 1,
                                                viewCount: 1,
                                                clickCount: 0,
                                                hasRecording: false)
        // Invoke getDictionary
        let result = cxRum.getDictionary()
        XCTAssertNotNil(result[Keys.snapshotContext.rawValue] as? [String: Any])
        if let snapshot = result[Keys.snapshotContext.rawValue] as? [String: Any] {
            if let timeInMiliseconds = snapshot[Keys.timestamp.rawValue] as? Int {
                XCTAssertEqual(TimeInterval(timeInMiliseconds), TimeInterval(currentTime.timeIntervalSince1970.milliseconds))
            }
            XCTAssertEqual(snapshot[Keys.errorCount.rawValue] as? Int, 1)
            XCTAssertEqual(snapshot[Keys.viewCount.rawValue] as? Int, 1)
        }
    }
    
    func testGetDictionaryErrorSnapshot() {
        mockSpanData = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                                 Keys.eventType.rawValue: AttributeValue("error"),
                                                 Keys.source.rawValue: AttributeValue("console"),
                                                 Keys.environment.rawValue: AttributeValue("prod"),
                                                 Keys.userId.rawValue: AttributeValue("12345"),
                                                 Keys.userName.rawValue: AttributeValue("John Doe"),
                                                 Keys.userEmail.rawValue: AttributeValue("john.doe@example.com")],
                                    startTime: Date(), spanId: "20", traceId: "30")
        var cxRum = CxRum(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            viewManager: mockViewerManager,
            networkManager: mockNetworkManager,
            metricsManager: mockCxMetricsManager,
            userMetadata: ["userId": "12345"],
            labels: ["key": "value"]
        )
        
        let currentTime = Date()
        cxRum.snapshotContext = SnapshotContext(timestamp: currentTime.timeIntervalSince1970,
                                                errorCount: 1,
                                                viewCount: 1,
                                                clickCount: 0,
                                                hasRecording: false)
        // Invoke getDictionary
        let result = cxRum.getDictionary()
        XCTAssertNotNil(result[Keys.snapshotContext.rawValue] as? [String: Any])
        if let snapshot = result[Keys.snapshotContext.rawValue] as? [String: Any] {
            if let timeInMiliseconds = snapshot[Keys.timestamp.rawValue] as? Int {
                XCTAssertEqual(TimeInterval(timeInMiliseconds), TimeInterval(currentTime.timeIntervalSince1970.milliseconds))
            }
            XCTAssertEqual(snapshot[Keys.errorCount.rawValue] as? Int, 1)
            XCTAssertEqual(snapshot[Keys.viewCount.rawValue] as? Int, 1)
        }
    }
    
    func testGetDictionaryNavigationSnapshot() {
        mockSpanData = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                                 Keys.eventType.rawValue: AttributeValue("navigation"),
                                                 Keys.source.rawValue: AttributeValue("console"),
                                                 Keys.environment.rawValue: AttributeValue("prod"),
                                                 Keys.userId.rawValue: AttributeValue("12345"),
                                                 Keys.userName.rawValue: AttributeValue("John Doe"),
                                                 Keys.userEmail.rawValue: AttributeValue("john.doe@example.com")],
                                    startTime: Date(), spanId: "20", traceId: "30")
        var cxRum = CxRum(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            viewManager: mockViewerManager,
            networkManager: mockNetworkManager,
            metricsManager: mockCxMetricsManager,
            userMetadata: ["userId": "12345"],
            labels: ["key": "value"]
        )
        
        let currentTime = Date()
        cxRum.snapshotContext = SnapshotContext(timestamp: currentTime.timeIntervalSince1970,
                                                errorCount: 0,
                                                viewCount: 1,
                                                clickCount: 0,
                                                hasRecording: false)
        // Invoke getDictionary
        let result = cxRum.getDictionary()
        XCTAssertNotNil(result[Keys.snapshotContext.rawValue] as? [String: Any])
        if let snapshot = result[Keys.snapshotContext.rawValue] as? [String: Any] {
            if let timeInMiliseconds = snapshot[Keys.timestamp.rawValue] as? Int {
                XCTAssertEqual(TimeInterval(timeInMiliseconds), TimeInterval(currentTime.timeIntervalSince1970.milliseconds))
            }
            XCTAssertEqual(snapshot[Keys.errorCount.rawValue] as? Int, 0)
            XCTAssertEqual(snapshot[Keys.viewCount.rawValue] as? Int, 1)
        }
    }
    
    func testLastSnapshotEventTimeMoreThan60() {
        mockSpanData = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                                 Keys.eventType.rawValue: AttributeValue("navigation"),
                                                 Keys.source.rawValue: AttributeValue("console"),
                                                 Keys.environment.rawValue: AttributeValue("prod"),
                                                 Keys.userId.rawValue: AttributeValue("12345"),
                                                 Keys.userName.rawValue: AttributeValue("John Doe"),
                                                 Keys.userEmail.rawValue: AttributeValue("john.doe@example.com")],
                                    startTime: Date(), spanId: "20", traceId: "30")
        
        let oneMinuteInThePast: TimeInterval = -120
        
        // Get the current date and time
        let currentDate = Date()
        
        // Calculate the date and time 1 minute in the past
        let pastDate = currentDate.addingTimeInterval(oneMinuteInThePast)
        
        mockSessionManager.lastSnapshotEventTime = pastDate
        let cxRum = CxRum(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            viewManager: mockViewerManager,
            networkManager: mockNetworkManager,
            metricsManager: mockCxMetricsManager,
            userMetadata: ["userId": "12345"],
            labels: ["key": "value"]
        )
        XCTAssertNotNil(cxRum.snapshotContext)
        XCTAssertTrue(cxRum.isOneMinuteFromLastSnapshotPass)
    }
    
    func testAddScreenshotContextAddsExpectedValues() {
        // Arrange
        var cxRum = CxRum(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            viewManager: mockViewerManager,
            networkManager: mockNetworkManager,
            metricsManager: mockCxMetricsManager,
            userMetadata: ["userId": "12345"],
            labels: ["key": "value"]
        )
        cxRum.screenshotId = "abc123"
        cxRum.page = "2"
        let date = Date(timeIntervalSince1970: 1_000_000)
        cxRum.timeStamp = date.timeIntervalSince1970
        
        var result: [String: Any] = [:]
        
        // Act
        cxRum.addScreenshotContext(to: &result)
        
        // Assert
        guard let context = result[Keys.screenshotContext.rawValue] as? [String: Any] else {
            XCTFail("Expected screenshotContext to be present")
            return
        }
        
        XCTAssertEqual(context[Keys.screenshotId.rawValue] as? String, "abc123")
        XCTAssertEqual(context[Keys.page.rawValue] as? Int, 2)
        XCTAssertEqual(context[Keys.segmentTimestamp.rawValue] as? Int, Int(date.timeIntervalSince1970 * 1000))
    }
    
    func testAddScreenshotContextDoesNothingWhenValuesAreNil() {
        // Arrange
        var cxRum = CxRum(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            viewManager: mockViewerManager,
            networkManager: mockNetworkManager,
            metricsManager: mockCxMetricsManager,
            userMetadata: ["userId": "12345"],
            labels: ["key": "value"]
        )
        cxRum.screenshotId = nil
        cxRum.page = nil
        var result: [String: Any] = ["existingKey": "value"]
        
        // Act
        cxRum.addScreenshotContext(to: &result)
        
        // Assert
        XCTAssertNil(result[Keys.screenshotContext.rawValue])
        XCTAssertEqual(result["existingKey"] as? String, "value")
    }
    
    func test_handleEvent_snapshotAfterOneMinute() {
        // Arrange
        mockSessionManager.lastSnapshotEventTime = Date(timeIntervalSince1970: 1000)
        var cxRum = CxRum(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            viewManager: mockViewerManager,
            networkManager: mockNetworkManager,
            metricsManager: mockCxMetricsManager,
            userMetadata: ["userId": "12345"],
            labels: ["key": "value"]
        )
        cxRum.timeStamp = 1000 + 61 // More than 1 minute later
        
        let attributes: [String: Any] = [
            Keys.eventType.rawValue: AttributeValue("unknown"),
            Keys.source.rawValue: AttributeValue("userAction"),
            Keys.severity.rawValue: AttributeValue("1")
        ]
        mockSpanData = MockSpanData(attributes: attributes)
        let eventContext = EventContext(otel: mockSpanData)
        cxRum.updateSnapshotContextIfNeeded(for: eventContext)
        XCTAssertTrue(cxRum.isOneMinuteFromLastSnapshotPass)
        XCTAssertNotNil(cxRum.snapshotContext)
    }
    
    func test_handleEvent_errorIncrementsCounterAndSnapshot() {
        var cxRum = CxRum(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            viewManager: mockViewerManager,
            networkManager: mockNetworkManager,
            metricsManager: mockCxMetricsManager,
            userMetadata: ["userId": "12345"],
            labels: ["key": "value"]
        )
        cxRum.timeStamp = 2000
        
        let attributes: [String: Any] = [
            Keys.eventType.rawValue: AttributeValue("error"),
            Keys.source.rawValue: AttributeValue("console"),
            Keys.severity.rawValue: AttributeValue("5")
        ]
        mockSpanData = MockSpanData(attributes: attributes)
        let eventContext = EventContext(otel: mockSpanData)
        XCTAssertTrue(mockSessionManager.getErrorCount() == 0)
        cxRum.updateSnapshotContextIfNeeded(for: eventContext)
        XCTAssertTrue(mockSessionManager.getErrorCount() == 1)
        XCTAssertNotNil(cxRum.snapshotContext)
    }
    
    func test_handleEvent_navigationTriggersSnapshot() {
        var cxRum = CxRum(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            viewManager: mockViewerManager,
            networkManager: mockNetworkManager,
            metricsManager: mockCxMetricsManager,
            userMetadata: ["userId": "12345"],
            labels: ["key": "value"]
        )
        cxRum.timeStamp = 3000

        let attributes: [String: Any] = [
            Keys.eventType.rawValue: AttributeValue("navigation"),
            Keys.source.rawValue: AttributeValue("console"),
            Keys.severity.rawValue: AttributeValue("1")
        ]
        mockSpanData = MockSpanData(attributes: attributes)
        let eventContext = EventContext(otel: mockSpanData)
        cxRum.updateSnapshotContextIfNeeded(for: eventContext)
        XCTAssertNotNil(cxRum.snapshotContext)
    }
    
    func test_handleEvent_guardFails_noCrash() {
        var cxRum = CxRum(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            viewManager: mockViewerManager,
            networkManager: mockNetworkManager,
            metricsManager: mockCxMetricsManager,
            userMetadata: ["userId": "12345"],
            labels: ["key": "value"]
        )
        cxRum.sessionManager?.lastSnapshotEventTime = nil  // Forces this part to not run

        cxRum.timeStamp = 3000
        let attributes: [String: Any] = [
            Keys.eventType.rawValue: AttributeValue("unknown"),
            Keys.source.rawValue: AttributeValue("console"),
            Keys.severity.rawValue: AttributeValue("1")
        ]
        mockSpanData = MockSpanData(attributes: attributes)
        let eventContext = EventContext(otel: mockSpanData)
        cxRum.updateSnapshotContextIfNeeded(for: eventContext)
        XCTAssertNil(cxRum.snapshotContext)
    }
    
    func test_buildSnapshotContext_returnsCorrectValues() {
        class MockSessionManager: SessionManager {
            override func getErrorCount() -> Int { return 5 }
            override func getClickCount() -> Int { return 12 }
        }
        
        class MockViewManager: ViewManager {
            override func getUniqueViewCount() -> Int { return 3 }
        }
        
        mockSessionManager = MockSessionManager()
        mockSessionManager.hasRecording = true
        mockViewerManager = MockViewManager(keyChain: MockKeyChain())
        let cxRum = CxRum(
            otel: mockSpanData,
            versionMetadata: mockVersionMetadata,
            sessionManager: mockSessionManager,
            viewManager: mockViewerManager,
            networkManager: mockNetworkManager,
            metricsManager: mockCxMetricsManager,
            userMetadata: ["userId": "12345"],
            labels: ["key": "value"]
        )
        
        let snapshotContext = cxRum.buildSnapshotContext(sessionManager: mockSessionManager,
                                                         viewManager: mockViewerManager)
        // Assert
        XCTAssertEqual(snapshotContext.errorCount, 5)
        XCTAssertEqual(snapshotContext.viewCount, 3)
        XCTAssertEqual(snapshotContext.actionCount, 12)
        XCTAssertEqual(snapshotContext.hasRecording, true)
        
        // Optionally test timestamp is recent (within 1 second)
        let currentTime = Date().timeIntervalSince1970
        XCTAssertLessThanOrEqual(abs(currentTime - snapshotContext.timestamp), 1.0)
    }
}
