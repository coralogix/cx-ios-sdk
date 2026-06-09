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
    var decrementErrorCounterCallCount = 0

    override func getErrorCount() -> Int { return errorCount }
    override var lastSnapshotEventTime: Date? {
        get { return lastSnapshotTime }
        set { lastSnapshotTime = newValue }
    }

    override func incrementErrorCounter() {
        incrementErrorCounterCallCount += 1
        errorCount += 1
    }

    override func decrementErrorCounter() {
        decrementErrorCounterCallCount += 1
        if errorCount > 0 { errorCount -= 1 }
    }
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
            Keys.severity.rawValue: AttributeValue("5"),
            Keys.sessionId.rawValue: AttributeValue("session_001"),
            Keys.sessionCreationDate.rawValue: AttributeValue(1609459200)
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

    func test_build_whenLastSnapshotEventTimeIsNil_createsSnapshotForGenericEvent() {
        // GIVEN: No snapshot has been emitted yet (initial launch or just-rotated session)
        //        and a non-error/non-navigation event arrives.
        mockSessionManager.lastSnapshotTime = nil
        let eventContext = makeEventContext(severity: 3, type: "log")
        guard let sut = makeSUT() else { return XCTFail("Failed to instantiate CxRumBuilder") }

        // WHEN: We build the snapshot context
        let snapshotContext = sut.buildSnapshotContextIfNeeded(for: eventContext)

        // THEN: A snapshot should be created — nil means "throttle expired" so the
        // fresh session gets its first snapshot on the first qualifying event,
        // matching the intent documented in SessionManager.setupSessionMetadata().
        XCTAssertNotNil(snapshotContext, "Snapshot should be created when lastSnapshotEventTime is nil (fresh session).")
        XCTAssertEqual(mockSessionManager.incrementErrorCounterCallCount, 0, "Error counter should NOT be incremented for a log event.")
        XCTAssertNotNil(mockSessionManager.lastSnapshotTime, "Snapshot time should be updated after emission.")
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
                                                   Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                                   Keys.sessionId.rawValue: AttributeValue("session_001"),
                                                   Keys.sessionCreationDate.rawValue: AttributeValue(1609459200)],
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

    // MARK: - CX-44687: isNavigationEvent + viewNumber wire emission

    func test_build_isNavigationEvent_trueForNavigationType() {
        guard let cxRum = makeSUT(currentTime: Date(), eventType: "navigation")?.build() else {
            return XCTFail("build() returned nil for navigation event")
        }
        XCTAssertTrue(cxRum.isNavigationEvent)
    }

    func test_build_isNavigationEvent_falseForLog() {
        guard let cxRum = makeSUT(currentTime: Date(), eventType: "log")?.build() else {
            return XCTFail("build() returned nil for log event")
        }
        XCTAssertFalse(cxRum.isNavigationEvent)
    }

    func test_build_isNavigationEvent_falseForError() {
        guard let cxRum = makeSUT(currentTime: Date(), eventType: "error")?.build() else {
            return XCTFail("build() returned nil for error event")
        }
        XCTAssertFalse(cxRum.isNavigationEvent)
    }

    func test_build_isNavigationEvent_falseForNetworkRequest() {
        guard let cxRum = makeSUT(currentTime: Date(), eventType: "network-request")?.build() else {
            return XCTFail("build() returned nil for network-request event")
        }
        XCTAssertFalse(cxRum.isNavigationEvent)
    }

    func test_build_viewNumber_nilBeforeAnyView() {
        // ViewManager fresh — no view has been set.
        mockViewManager = MockViewManager(keyChain: MockKeyChain())
        guard let cxRum = makeSUT(currentTime: Date(), eventType: "log")?.build() else {
            return XCTFail("build() returned nil")
        }
        XCTAssertNil(cxRum.viewNumber,
                     "events fired before any view appears must omit view_number")
    }

    func test_build_viewNumber_propagatesFromViewManager() {
        // Drive ViewManager through 3 distinct appearances → expect view_number = 2.
        mockViewManager = MockViewManager(keyChain: MockKeyChain())
        mockViewManager.set(cxView: CXView(state: .notifyOnAppear, name: "A"))
        mockViewManager.set(cxView: CXView(state: .notifyOnAppear, name: "B"))
        mockViewManager.set(cxView: CXView(state: .notifyOnAppear, name: "C"))

        guard let cxRum = makeSUT(currentTime: Date(), eventType: "log")?.build() else {
            return XCTFail("build() returned nil")
        }
        XCTAssertEqual(cxRum.viewNumber, 2)
    }

    func test_payload_emitsIsNavigationEventAtTopLevel() {
        guard let cxRum = makeSUT(currentTime: Date(), eventType: "log")?.build() else {
            return XCTFail("build() returned nil")
        }
        var builder = CxRumPayloadBuilder(rum: cxRum, viewManager: mockViewManager)
        let payload = builder.build()

        // Must appear at cx_rum top level, NOT inside view_context / event_context.
        XCTAssertNotNil(payload[Keys.isNavigationEvent.rawValue],
                        "isNavigationEvent must be emitted at the cx_rum top level on every event")
        XCTAssertEqual(payload[Keys.isNavigationEvent.rawValue] as? Bool, false)

        // Confirm it's NOT nested under event_context.
        let ec = payload[Keys.eventContext.rawValue] as? [String: Any]
        XCTAssertNil(ec?[Keys.isNavigationEvent.rawValue],
                     "isNavigationEvent must not be nested under event_context")
    }

    func test_payload_emitsViewNumberAtTopLevelWhenPresent() {
        mockViewManager = MockViewManager(keyChain: MockKeyChain())
        mockViewManager.set(cxView: CXView(state: .notifyOnAppear, name: "Home"))
        mockViewManager.set(cxView: CXView(state: .notifyOnAppear, name: "Settings"))

        guard let cxRum = makeSUT(currentTime: Date(), eventType: "log")?.build() else {
            return XCTFail("build() returned nil")
        }
        var builder = CxRumPayloadBuilder(rum: cxRum, viewManager: mockViewManager)
        let payload = builder.build()

        XCTAssertEqual(payload[Keys.viewNumber.rawValue] as? Int, 1)

        // Must NOT be nested under view_context.
        let vc = payload[Keys.viewContext.rawValue] as? [String: Any]
        XCTAssertNil(vc?[Keys.viewNumber.rawValue],
                     "view_number must not be nested under view_context")
    }

    func test_payload_omitsViewNumberWhenNoViewYet() {
        mockViewManager = MockViewManager(keyChain: MockKeyChain())
        // No views set — viewNumber should be nil.

        guard let cxRum = makeSUT(currentTime: Date(), eventType: "log")?.build() else {
            return XCTFail("build() returned nil")
        }
        var builder = CxRumPayloadBuilder(rum: cxRum, viewManager: mockViewManager)
        let payload = builder.build()

        XCTAssertNil(payload[Keys.viewNumber.rawValue],
                     "view_number must be entirely absent from the payload when no view has appeared yet")
    }

    // Convenience overload that lets the new tests vary event type without touching the
    // original makeSUT() / its existing callers (which pin a "log" event for snapshot tests).
    private func makeSUT(currentTime: Date, eventType: String) -> CxRumBuilder? {
        let endTime = Date()
        self.mockOtel = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                                  Keys.eventType.rawValue: AttributeValue(eventType),
                                                  Keys.source.rawValue: AttributeValue("console"),
                                                  Keys.environment.rawValue: AttributeValue("prod"),
                                                  Keys.userId.rawValue: AttributeValue("12345"),
                                                  Keys.userName.rawValue: AttributeValue("John Doe"),
                                                  Keys.userEmail.rawValue: AttributeValue("john.doe@example.com"),
                                                  Keys.sessionId.rawValue: AttributeValue("session_001"),
                                                  Keys.sessionCreationDate.rawValue: AttributeValue(1609459200)],
                                     startTime: currentTime,
                                     endTime: endTime,
                                     spanId: "20",
                                     traceId: "30",
                                     name: "testSpan",
                                     kind: 1,
                                     statusCode: ["status": "ok"],
                                     resources: [:])

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
                                           ignoreUrls: [],
                                           ignoreErrors: [],
                                           labels: ["key": "value"],
                                           debug: true)
        guard let options = options else { return nil }

        return CxRumBuilder(otel: mockOtel,
                            versionMetadata: VersionMetadata(appName: "Test", appVersion: "1.0"),
                            sessionManager: mockSessionManager,
                            viewManager: mockViewManager,
                            networkManager: NetworkManager(),
                            options: options)
    }
}
