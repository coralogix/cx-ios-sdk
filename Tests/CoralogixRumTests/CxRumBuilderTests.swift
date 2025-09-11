//
//  CxRumBuilderTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 11/09/2025.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

class MockSessionManager: SessionManager {
    var lastSnapshotTime: Date?
    var errorCount = 0
    var clickCount = 0
    var hasRec = false
    
    var incrementErrorCounterCallCount = 0
    
    override func getErrorCount() -> Int { return errorCount }
    override var lastSnapshotEventTime: Date? {
        get { return lastSnapshotTime }
        set { lastSnapshotTime = newValue }
    }
    
    override func incrementErrorCounter() {
        incrementErrorCounterCallCount += 1
        errorCount += 1
    }
    
    // Add other overrides as needed, returning default values
}

class MockViewManager: ViewManager {
    var uniqueViewCount = 0
    override func getUniqueViewCount() -> Int {
        return uniqueViewCount
    }
}

class CxRumBuilderTests: XCTestCase {
    
    var sut: CxRumBuilder! // System Under Test
    var mockSessionManager: MockSessionManager!
    var mockViewManager: MockViewManager!
    var mockOtel: MockSpanData!
    var mockVersionMetadata: VersionMetadata!
    var mockViewerManager: ViewManager!
    var mockNetworkManager: NetworkManager!
    var options: CoralogixExporterOptions?
    var mockSpanData: SpanDataProtocol!
    
    let statTime = Date()
    let endTime = Date()
    
    // This method is called before each test
    override func setUp() {
        super.setUp()
        
        mockSessionManager = MockSessionManager()
        mockNetworkManager = NetworkManager()
        
        mockViewManager = MockViewManager(keyChain: KeychainManager())
        mockVersionMetadata = VersionMetadata(appName: "ExampleApp", appVersion: "1.1.1")
        
        mockSpanData = MockSpanData(attributes: [
            Keys.eventType.rawValue: AttributeValue("error"),
            Keys.source.rawValue: AttributeValue("userAction"),
            Keys.severity.rawValue: AttributeValue("5")
        ])
    }
    
    // This method is called after each test
    override func tearDown() {
        sut = nil
        mockOtel = nil
        mockSpanData = nil
        mockSessionManager = nil
        mockViewManager = nil
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func test_build_whenIsError_createsSnapshotAndIncrementsCounter() {
        // GIVEN: An error event
        let eventContext = makeEventContext(severity: 5, type: "log")
        guard let sut = makeSUT() else { return XCTFail("Failed to instantiate CxRumBuilder") }
        
        // WHEN: We build the snapshot context
        let snapshotContext = sut.buildSnapshotContextIfNeeded(for: eventContext)
        
        // THEN: A snapshot should be created and the counter incremented
        XCTAssertNotNil(snapshotContext, "Snapshot context should be created for an error event.")
        XCTAssertEqual(mockSessionManager.incrementErrorCounterCallCount, 1, "Error counter should be incremented.")
        XCTAssertNotNil(mockSessionManager.lastSnapshotTime, "Snapshot time should be updated.")
    }
    
    func test_build_whenIsNavigation_createsSnapshotWithoutIncrementingCounter() {
        // GIVEN: A navigation event
        let eventContext = makeEventContext(severity: 3, type: "navigation")
        guard let sut = makeSUT() else { return XCTFail("Failed to instantiate CxRumBuilder") }
        
        // WHEN: We build the snapshot context
        let snapshotContext = sut.buildSnapshotContextIfNeeded(for: eventContext)
        
        // THEN: A snapshot should be created but the error counter should NOT be incremented
        XCTAssertNotNil(snapshotContext, "Snapshot context should be created for a navigation event.")
        XCTAssertEqual(mockSessionManager.incrementErrorCounterCallCount, 0, "Error counter should NOT be incremented.")
        XCTAssertNotNil(mockSessionManager.lastSnapshotTime, "Snapshot time should be updated.")
    }
    
    func test_build_whenNoConditionsMet_returnsNil() {
        // GIVEN: A normal event and a recent snapshot
        mockSessionManager.lastSnapshotTime = Date().addingTimeInterval(-30)
        let eventContext = makeEventContext(severity: 3, type: "log")
        guard let sut = makeSUT(currentTime: Date()) else { return XCTFail("Failed to instantiate CxRumBuilder") }
        let initialSnapshotTime = mockSessionManager.lastSnapshotTime
        
        // WHEN: We build the snapshot context
        let snapshotContext = sut.buildSnapshotContextIfNeeded(for: eventContext)
        
        // THEN: No snapshot should be created
        XCTAssertNil(snapshotContext, "Snapshot context should be nil when no conditions are met.")
        XCTAssertEqual(mockSessionManager.incrementErrorCounterCallCount, 0, "Error counter should NOT be incremented.")
        XCTAssertEqual(mockSessionManager.lastSnapshotTime, initialSnapshotTime, "Snapshot time should NOT be updated.")
    }
    
    func test_build_whenOneMinuteHasPassed_createsSnapshot() {
        // GIVEN: The last snapshot was over a minute ago, controlled precisely
        let now = Date()
        let eventContext = makeEventContext(severity: 3, type: "log")
        guard let sut = makeSUT(currentTime: now) else { return XCTFail("Failed to instantiate CxRumBuilder") }

        mockSessionManager.lastSnapshotTime = now.addingTimeInterval(-61)
        
        // WHEN: We build the snapshot context
        let snapshotContext = sut.buildSnapshotContextIfNeeded(for: eventContext)
        
        // THEN: A snapshot should be created
        XCTAssertNotNil(snapshotContext, "Snapshot context should be created when one minute has passed.")
        XCTAssertEqual(mockSessionManager.incrementErrorCounterCallCount, 0, "Error counter should NOT be incremented.")
        XCTAssertNotNil(mockSessionManager.lastSnapshotTime, "Snapshot time should be updated.")
    }
    
    
    private func makeSUT(currentTime: Date = Date()) -> CxRumBuilder? {
        // This helper creates the System Under Test with a controlled start time
        let endTime = Date()
        self.mockOtel =  MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                                   Keys.eventType.rawValue: AttributeValue("log"),
                                                   Keys.source.rawValue: AttributeValue("console"),
                                                   Keys.environment.rawValue: AttributeValue("prod"),
                                                   Keys.userId.rawValue: AttributeValue("12345"),
                                                   Keys.userName.rawValue: AttributeValue("John Doe"),
                                                   Keys.userEmail.rawValue: AttributeValue("john.doe@example.com")],
                                      startTime: currentTime,
                                      endTime: endTime,
                                      spanId: "20",
                                      traceId: "30",
                                      name: "testSpan",
                                      kind: 1,
                                      statusCode: ["status": "ok"],
                                      resources: ["a": AttributeValue("1"),
                                                  "b": AttributeValue("2"),
                                                  "c": AttributeValue("3")])
        
        let userContext = UserContext(userId: "12345",
                                      userName: "John Doe",
                                      userEmail: "john.doe@example.com",
                                      userMetadata: ["userId": "12345"])
        
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
        
        guard let options = options else { return nil }
        
        return CxRumBuilder(
            otel: mockOtel,
            versionMetadata: VersionMetadata(appName: "Test", appVersion: "1.0"),
            sessionManager: mockSessionManager,
            viewManager: mockViewManager,
            networkManager: NetworkManager(), // Can also be mocked if needed
            options: options
        )
    }
    
    
    private func makeEventContext(severity: Int, type: String) -> EventContext {
        let mockSpanData = MockSpanData(attributes: [
            Keys.severity.rawValue: AttributeValue("\(severity)"),
            Keys.eventType.rawValue: AttributeValue(type)
        ])
        return EventContext(otel: mockSpanData)
    }
}
