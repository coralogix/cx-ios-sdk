import XCTest
import CoralogixInternal
@testable import Coralogix

final class CoralogixRumTests: XCTestCase {
    var options: CoralogixExporterOptions?
    
    override func setUpWithError() throws {
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                           userContext: nil,
                                           environment: "PROD",
                                           application: "TestApp-iOS",
                                           version: "1.0",
                                           publicKey: "token",
                                           ignoreUrls: [], //[".*\\.il$", "https://www.coralogix.com/academy"],
                                           ignoreErrors: [], //[".*errorcode=.*", "Im cusom Error"],
                                           labels: ["item" : "banana", "itemPrice" : 1000],
                                           sampleRate: 100,
                                           debug: true)
    }
    
    override func tearDownWithError() throws {
        options = nil
    }
    
    func testInit() {
        let coralogixRum = CoralogixRum(options: options!)
        if let options = coralogixRum.coralogixExporter?.getOptions() {
            
            // Verify that options are set correctly
            XCTAssertEqual(options.application, "TestApp-iOS")
            XCTAssertEqual(options.version, "1.0")
            
            // Verify that isDebug flag is set correctly
            XCTAssertTrue(Log.isDebug)
            
            // Verify that isInitialized flag is set to true
            XCTAssertTrue(CoralogixRum.isInitialized)
        }
    }
    
    func testInitSamplerOff() {
        CoralogixRum.isInitialized = false
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                           userContext: nil,
                                           environment: "PROD",
                                           application: "TestApp-iOS",
                                           version: "1.0",
                                           publicKey: "token",
                                           ignoreUrls: [], //[".*\\.il$", "https://www.coralogix.com/academy"],
                                           ignoreErrors: [], //[".*errorcode=.*", "Im cusom Error"],
                                           labels: ["item" : "banana", "itemPrice" : 1000],
                                           sampleRate: 0,
                                           debug: true)
        _ = CoralogixRum(options: options!)
        XCTAssertFalse(CoralogixRum.isInitialized)
    }
    
    // Test setUserContext method
    func testSetUserContext() {
        let coralogixRum = CoralogixRum(options: options!)
            let userContext = UserContext(userId: "1234",
                                          userName: "Daffy Duck",
                                          userEmail: "daffy.duck@coralogix.com",
                                          userMetadata: ["age": "18", "profession" : "duck"])
            coralogixRum.setUserContext(userContext: userContext)
            
        if let options = coralogixRum.coralogixExporter?.getOptions() {
            
            // Verify that userContext is set correctly
            XCTAssertEqual(options.userContext, userContext)
        }

    }
    
    func testSetLabels() {
        let coralogixRum = CoralogixRum(options: options!)
        if let labels = coralogixRum.coralogixExporter?.getOptions().labels {
            XCTAssertEqual(labels.count, 2)
            XCTAssertEqual(labels["item"] as? String, "banana")
            XCTAssertEqual(labels["itemPrice"] as? Int, 1000)
        }
        
        let newLabel = ["device": "iphone"]
        coralogixRum.setLabels(labels: newLabel)
        if let labels = coralogixRum.coralogixExporter?.getOptions().labels {
            XCTAssertEqual(labels.count, 1)
            XCTAssertEqual(labels["device"] as? String, "iphone")
        }
    }
    
    func testShutdown() {
        let coralogixRum = CoralogixRum(options: options!)
        coralogixRum.shutdown()
        XCTAssertFalse(CoralogixRum.isInitialized)
    }
    
    func testHasSessionRecording() {
        var coralogixRum = CoralogixRum(options: options!)
        let mockSessionManager = SessionManager()
        let mockOptions =  CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                                           userContext: nil,
                                                           environment: "PROD",
                                                           application: "TestApp-iOS",
                                                           version: "1.0",
                                                           publicKey: "token",
                                                           ignoreUrls: [],
                                                           ignoreErrors: [],
                                                           labels: ["item" : "banana", "itemPrice" : 1000],
                                                           sampleRate: 100,
                                                           debug: true)
        coralogixRum = CoralogixRum(options: mockOptions, sessionManager: mockSessionManager)
        
        // Test enabling session recording
        coralogixRum.hasSessionRecording(true)
        XCTAssertTrue(mockSessionManager.hasRecording)

        // Test disabling session recording
        coralogixRum.hasSessionRecording(false)
        XCTAssertFalse(mockSessionManager.hasRecording)
    }
    
    func testIsDebug() {
        var mockOptions =  CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                                    userContext: nil,
                                                    environment: "PROD",
                                                    application: "TestApp-iOS",
                                                    version: "1.0",
                                                    publicKey: "token",
                                                    ignoreUrls: [],
                                                    ignoreErrors: [],
                                                    labels: ["item" : "banana", "itemPrice" : 1000],
                                                    sampleRate: 100,
                                                    debug: true)
        var coralogixRum = CoralogixRum(options: mockOptions)
        // Test when debug is true
        XCTAssertTrue(coralogixRum.isDebug())
        
        // Test when debug is false
        CoralogixRum.isInitialized = false
        mockOptions =  CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                                userContext: nil,
                                                environment: "PROD",
                                                application: "TestApp-iOS",
                                                version: "1.0",
                                                publicKey: "token",
                                                ignoreUrls: [],
                                                ignoreErrors: [],
                                                labels: ["item" : "banana", "itemPrice" : 1000],
                                                sampleRate: 100,
                                                debug: false)
        coralogixRum = CoralogixRum(options: mockOptions)
        XCTAssertFalse(coralogixRum.isDebug())
    }
    
    func testGetSessionCreationTimestamp() {
        let mockSessionManager = SessionManager()
        let mockOptions =  CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                                    userContext: nil,
                                                    environment: "PROD",
                                                    application: "TestApp-iOS",
                                                    version: "1.0",
                                                    publicKey: "token",
                                                    ignoreUrls: [],
                                                    ignoreErrors: [],
                                                    labels: ["item" : "banana", "itemPrice" : 1000],
                                                    sampleRate: 100,
                                                    debug: true)
        let coralogixRum = CoralogixRum(options: mockOptions, sessionManager: mockSessionManager)

        // Test with a valid session metadata
        XCTAssertNotNil(coralogixRum.getSessionCreationTimestamp())
    }
    
    func testHandleAppearStateIfNeededWhenStateIsNotifyOnAppearShouldCaptureEventAndSetSpanAttribute() {
        let coralogixRum = makeMockCoralogixRum()
        let mockSpan = MockSpan()

        // Arrange
        let view = CXView(state: .notifyOnAppear, name: "home")
        let mockSessionReplay =  MockSessionReplay()
        SdkManager.shared.register(sessionReplayInterface: mockSessionReplay)
        // Act
        coralogixRum.handleAppearStateIfNeeded(cxView: view, span: mockSpan)
        
        // Assert
        XCTAssertNotNil(mockSessionReplay.captureEventCalledWith, "Expected SessionReplay.captureEvent to be invoked")
        XCTAssertNotNil(mockSessionReplay.captureEventCalledWith?[Keys.screenshotId.rawValue] as? String, "Expected screenshotId to be present in captured metadata")
       
        XCTAssertTrue(mockSpan.setAttributeCalled)
        XCTAssertNotNil(mockSpan.setAttributeKey)
        XCTAssertNotNil(mockSpan.setAttributeValue)
        SdkManager.shared.register(sessionReplayInterface: nil)
    }
    
    func testHandleAppearStateIfNeededWhenStateIsNotNotifyOnAppearShouldNotCaptureEvent() {
        let coralogixRum = makeMockCoralogixRum()
        let mockSpan = MockSpan()
        let mockSessionReplay =  MockSessionReplay()

        // Arrange
        let view = CXView(state: .notifyOnDisappear, name: "home")

        // Act
        SdkManager.shared.register(sessionReplayInterface: mockSessionReplay)
        coralogixRum.handleAppearStateIfNeeded(cxView: view, span: mockSpan)

        // Assert
        XCTAssertNil(mockSessionReplay.captureEventCalledWith)
        XCTAssertFalse(mockSpan.setAttributeCalled)
    }
    
    func testHandleAppearStateIfNeededWhenSessionReplayIsNilShouldNotCrashOrCaptureEvent() {

        SdkManager.shared.register(sessionReplayInterface: nil)
        let coralogixRum = makeMockCoralogixRum()
        let mockSpan = MockSpan()

        let view = CXView(state: .notifyOnAppear, name: "home")
        
        // Act
        coralogixRum.handleAppearStateIfNeeded(cxView: view, span: mockSpan)
        
        // Assert
        XCTAssertFalse(mockSpan.setAttributeCalled)
    }
    
    func testGetNavigationSpanShouldSetCorrectAttributes() {
        let coralogixRum = makeMockCoralogixRum()
        
        coralogixRum.tracerProvider = {
            return MockTracer()
        }

        if let mockSpan = coralogixRum.getNavigationSpan() as? MockSpan {
            // Assert
            XCTAssertEqual(mockSpan.recordedAttributes[Keys.eventType.rawValue], .string(CoralogixEventType.navigation.rawValue))
            XCTAssertEqual(mockSpan.recordedAttributes[Keys.source.rawValue], .string(Keys.console.rawValue))
            XCTAssertEqual(mockSpan.recordedAttributes[Keys.severity.rawValue], .int(CoralogixLogSeverity.info.rawValue))
        }
    }
    
    func testHandleUniqueViewIfNeededWhenUniqueViewShouldSetSnapshotContextAttribute() {
        let coralogixRum = makeMockCoralogixRum()
        let cxView = CXView(state: .notifyOnDisappear, name: "TestView")
        let mockSpan = MockSpan()
        
        // Act
        coralogixRum.handleUniqueViewIfNeeded(cxView: cxView, span: mockSpan)
        
        // Assert
        XCTAssertTrue(mockSpan.setAttributeCalled, "Expected span.setAttribute to be called.")
        XCTAssertEqual(mockSpan.setAttributeKey, Keys.snapshotContext.rawValue, "Expected the attribute key to be snapshotContext.")
        
        if case let .string(jsonString)? = mockSpan.setAttributeValue {
            XCTAssertTrue(jsonString.contains("\"errorCount\":0"), "Expected error count to be 0.")
            XCTAssertTrue(jsonString.contains("\"viewCount\":1"), "Expected view count to be 1.")
            XCTAssertTrue(jsonString.contains("\"clickCount\":0"), "Expected click count to be 0.")
            XCTAssertTrue(jsonString.contains("\"hasRecording\":false"), "Expected hasRecording to be false.")
        } else {
            XCTFail("Expected setAttribute value to be a JSON string.")
        }
    }
    
    func testHandleUniqueViewIfNeededWhenSessionManagerIsNilShouldNotSetAttribute() {
        let coralogixRum = makeMockCoralogixRum()
        let cxView = CXView(state: .notifyOnDisappear, name: "TestView")
        let mockSpan = MockSpan()

        coralogixRum.sessionManager = nil // 🚨 Important! Simulate missing session
            
        // Act
        coralogixRum.handleUniqueViewIfNeeded(cxView: cxView, span: mockSpan)
            
        // Assert
        XCTAssertFalse(mockSpan.setAttributeCalled, "Expected no attribute to be set when sessionManager is nil.")
    }
    
    func testHandleNotificationShouldSetCxViewInExporter() {
        let mockOptions =  CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                                    userContext: nil,
                                                    environment: "PROD",
                                                    application: "TestApp-iOS",
                                                    version: "1.0",
                                                    publicKey: "token",
                                                    ignoreUrls: [],
                                                    ignoreErrors: [],
                                                    sampleRate: 100,
                                                    debug: true)
        let coralogixRum =  CoralogixRum(options: mockOptions)
        let cxView = CXView(state: .notifyOnDisappear, name: "TestView")
        let mockSessionManager = SessionManager()

        let mockExporter = MockCoralogixExporter(options: mockOptions,
                                                 sessionManager: mockSessionManager,
                                                 networkManager: NetworkManager(),
                                                 viewManager: ViewManager(keyChain: nil),
                                                 metricsManager: MetricsManager())
        coralogixRum.coralogixExporter = mockExporter
        let notification = Notification(name: Notification.Name("TestNotification"), object: cxView, userInfo: nil)
        
        // Act
        coralogixRum.handleNotification(notification: notification)
        
        // Assert
        XCTAssertTrue(mockExporter.setCalled, "Expected coralogixExporter.set(cxView:) to be called.")
        XCTAssertEqual(mockExporter.capturedCxView?.name, cxView.name, "Expected captured CXView to match the one from notification.")
    }
    
    func testHandleNotificationWithInvalidObjectShouldNotCallSetOnExporter() {
        // Arrange
        let mockOptions =  CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                                    userContext: nil,
                                                    environment: "PROD",
                                                    application: "TestApp-iOS",
                                                    version: "1.0",
                                                    publicKey: "token",
                                                    ignoreUrls: [],
                                                    ignoreErrors: [],
                                                    sampleRate: 100,
                                                    debug: true)
        let coralogixRum = CoralogixRum(options: mockOptions)
        let invalidObject = "Not a CXView" // String instead of CXView
        let mockSessionManager = SessionManager()

        let mockExporter = MockCoralogixExporter(options: mockOptions,
                                                 sessionManager: mockSessionManager,
                                                 networkManager: NetworkManager(),
                                                 viewManager: ViewManager(keyChain: nil),
                                                 metricsManager: MetricsManager())
        coralogixRum.coralogixExporter = mockExporter
        let notification = Notification(name: Notification.Name("TestNotification"), object: invalidObject, userInfo: nil)
        
        // Act
        coralogixRum.handleNotification(notification: notification)
        
        // Assert
        XCTAssertFalse(mockExporter.setCalled, "Expected coralogixExporter.set(cxView:) NOT to be called when object is invalid.")
    }
    
    func testBuildMetadataMergesCorrectly() {
        let coralogixRum = makeMockCoralogixRum()
        let properties: [String: Any] = [
            "key1": "value1",
            "key2": 123
        ]
        let screenshotId = "screenshot_001"
        let screenshotData = "fakeImage".data(using: .utf8)
        
        let screenshotLocation = ScreenshotLocation(segmentIndex: 0, page: 0, screenshotId: screenshotId)
        let result = coralogixRum.buildMetadata(properties: properties,
                                                screenshotLocation: screenshotLocation,
                                                screenshotData: screenshotData)
        // Assert
        XCTAssertNil(result["timestamp"] as? TimeInterval)
        XCTAssertEqual(result["screenshotId"] as? String, screenshotId)
        XCTAssertEqual(result[Keys.screenshotData.rawValue] as? Data, screenshotData)
        XCTAssertEqual(result[Keys.page.rawValue] as? Int, 0)
        XCTAssertEqual(result[Keys.segmentIndex.rawValue] as? Int, 0)
        XCTAssertEqual(result[Keys.screenshotId.rawValue] as? String, screenshotId)
        XCTAssertEqual(result["key1"] as? String, "value1")
        XCTAssertEqual(result["key2"] as? Int, 123)
    }

    func testContainsXYReturnsTrueWhenBothKeysExist() {
        let coralogixRum = makeMockCoralogixRum()
        let dict: [String: Any] = [
            Keys.positionX.rawValue: 100,
            Keys.positionY.rawValue: 200
        ]
        
        // Act
        let result = coralogixRum.containsXY(dict)
        
        // Assert
        XCTAssertTrue(result)
    }
    
    func testContainsXYReturnsFalseWhenOnlyXExists() {
        let coralogixRum = makeMockCoralogixRum()
        let dict: [String: Any] = [
            Keys.positionX.rawValue: 100
        ]
        
        // Act
        let result = coralogixRum.containsXY(dict)
        
        // Assert
        XCTAssertFalse(result)
    }
    
    func testContainsXYReturnsFalseWhenOnlyYExists() {
        let coralogixRum = makeMockCoralogixRum()
        let dict: [String: Any] = [
            Keys.positionY.rawValue: 200
        ]
        
        // Act
        let result = coralogixRum.containsXY(dict)
        
        // Assert
        XCTAssertFalse(result)
    }
    
    func testContainsXYReturnsFalseWhenNeitherExist() {
        let coralogixRum = makeMockCoralogixRum()
        
        let dict: [String: Any] = [
            "someKey": "someValue"
        ]
        
        // Act
        let result = coralogixRum.containsXY(dict)
        
        // Assert
        XCTAssertFalse(result)
    }
    
    func testGetUserActionsSpanSetsCorrectAttributes() {
        let coralogixRum = makeMockCoralogixRum()
        coralogixRum.tracerProvider = {
            return MockTracer()
        }
        let span = coralogixRum.getUserActionsSpan()
        
        guard let mockSpan = span as? MockSpan else {
            XCTFail("Expected span to be MockSpan")
            return
        }
           
        // Assert
        // Assuming your Span protocol has methods to retrieve attributes
        XCTAssertEqual(span.name, Keys.iosSdk.rawValue)
        
        if case let .string(value)? = mockSpan.recordedAttributes[Keys.eventType.rawValue] {
            XCTAssertEqual(value, CoralogixEventType.userInteraction.rawValue)
        } else {
            XCTFail("Expected eventType to be a string")
        }
        
        // Assert: Check severity
        if case let .int(value)? = mockSpan.recordedAttributes[Keys.severity.rawValue] {
            XCTAssertEqual(value, CoralogixLogSeverity.info.rawValue)
        } else {
            XCTFail("Expected severity to be an int")
        }
    }
    
    func testHandleUserInteractionEventCapturesEventAndEndsSpan() {
        // Arrange
        let coralogixRum = makeMockCoralogixRum()
        coralogixRum.tracerProvider = {
            return MockTracer()
        }
        let mockSpan = MockSpan()
        let mockSessionReplay = MockSessionReplay()
        SdkManager.shared.register(sessionReplayInterface: mockSessionReplay)
        
        // Act
        let testProperties: [String: Any] = [
            Keys.positionX.rawValue: 100,
            Keys.positionY.rawValue: 200,
            "testKey": "testValue"
        ]
        let window = UIWindow()
        window.makeKeyAndVisible()
        coralogixRum.handleUserInteractionEvent(testProperties, span: mockSpan, window: window)
        
        // Assert
        XCTAssertNotNil(mockSessionReplay.captureEventCalledWith, "Event was not captured")
        let required = [Keys.segmentIndex.rawValue,
                        Keys.page.rawValue,
                        Keys.screenshotId.rawValue,
                        Keys.screenshotData.rawValue,
                        Keys.positionX.rawValue,
                        Keys.positionY.rawValue,
                        "testKey"]
       XCTAssertTrue(required.allSatisfy { mockSessionReplay.captureEventCalledWith!.keys.contains($0) }, "Captured metadata is missing expected keys")
        
        let capturedMetadata = mockSessionReplay.captureEventCalledWith?.first
        XCTAssertNotNil(capturedMetadata)
        
        XCTAssertNotNil(mockSpan.recordedAttributes[Keys.screenshotId.rawValue], "Should set screenshotId on span")
        XCTAssertNotNil(mockSpan.recordedAttributes[Keys.tapObject.rawValue], "Should set tapObject on span")
        XCTAssertTrue(mockSpan.didEnd, "Span should be ended")
    }

    func testAddScreenshotIdAddsAttributeAndCapturesEvent() {
        // Arrange
        var span: any Span = MockSpan()
        let mockSessionReplay = MockSessionReplay()
        
        SdkManager.shared.register(sessionReplayInterface: mockSessionReplay)

        let coralogixRum = makeMockCoralogixRum()

        // Act
        coralogixRum.addScreenshotId(to: &span)
        
        guard let mockSpan = span as? MockSpan else {
            XCTFail("Span is not MockSpan")
            return
        }

        XCTAssertNotNil(mockSpan.recordedAttributes[Keys.screenshotId.rawValue], "ScreenshotId should be set on the span")
        XCTAssertNotNil(mockSessionReplay.captureEventCalledWith, "captureEvent should be invoked")
        if let capturedEvent = mockSessionReplay.captureEventCalledWith {
            XCTAssertEqual(Set(capturedEvent.keys),
                           [Keys.segmentIndex.rawValue, Keys.page.rawValue, Keys.screenshotId.rawValue],
                           "Unexpected keys in captured metadata")
        }
    }
    
    func testGetErrorSpanSetsAttributesAndCallsHelpers() {
        let mockSessionReplay = MockSessionReplay()
        SdkManager.shared.register(sessionReplayInterface: mockSessionReplay)
        let coralogixRum = makeMockCoralogixRum()
        coralogixRum.tracerProvider = {
            return MockTracer()
        }
        let span = coralogixRum.getErrorSpan()
        guard let mockSpan = span as? MockSpan else {
            XCTFail("Expected span to be MockSpan")
            return
        }
        XCTAssertEqual(mockSpan.recordedAttributes[Keys.eventType.rawValue], .string(CoralogixEventType.error.rawValue))
        XCTAssertEqual(mockSpan.recordedAttributes[Keys.source.rawValue], .string(Keys.console.rawValue))
        XCTAssertEqual(mockSpan.recordedAttributes[Keys.severity.rawValue], .int(CoralogixLogSeverity.error.rawValue))
    }
    
    private func makeMockCoralogixRum() ->  CoralogixRum {
        let mockOptions = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp-iOS",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            sampleRate: 100,
            debug: true
        )
        
        let coralogixRum = CoralogixRum(options: mockOptions)
        return coralogixRum
    }
}

final class MockCoralogixExporter: CoralogixExporter {
    var setCalled = false
    var capturedCxView: CXView?
    
    override func set(cxView: CXView) {
        setCalled = true
        capturedCxView = cxView
    }
}

final class MockTracer: Tracer {
    var mockSpanBuilder = MockSpanBuilder()
    
    func spanBuilder(spanName: String) -> SpanBuilder {
        return mockSpanBuilder
    }
    
    // If Tracer has more methods, stub them as no-op
}

final class MockSpanBuilder: SpanBuilder {
    func setAttribute(key: String, value: Coralogix.AttributeValue) -> Self {
        return self
    }
    
    func setParent(_ parent: any Coralogix.Span) -> Self {
        return self
    }
    
    func setParent(_ parent: Coralogix.SpanContext) -> Self {
        return self
    }
    
    func setNoParent() -> Self {
        return self
    }
    
    func addLink(spanContext: Coralogix.SpanContext) -> Self {
        return self
    }
    
    func addLink(spanContext: Coralogix.SpanContext, attributes: [String : Coralogix.AttributeValue]) -> Self {
        return self
    }
    
    func setSpanKind(spanKind: Coralogix.SpanKind) -> Self {
        return self
    }
    
    
    func setStartTime(time: Date) -> Self {
        return self
    }
    
    func setActive(_ active: Bool) -> Self {
        return self
    }
    
    var startedSpan: MockSpan?
    
    func startSpan() -> any Span {
        let span = MockSpan()
        startedSpan = span
        return span
    }
    
    // Other methods if needed
}

final class MockSessionReplay: SessionReplayInterface {
    var captureEventCalledWith: [String: Any]?
    
    func startRecording() {
        
    }
    
    func stopRecording() {
        
    }
    
    func captureEvent(properties: [String : Any]?) {
        captureEventCalledWith = properties
    }
    
    func update(sessionId: String) {
        
    }
}

final class MockSpan: Span {
    var didEnd = false
    var kind: SpanKind = .internal
    var recordedAttributes: [String: AttributeValue] = [:]
    var context: SpanContext = SpanContext.create(traceId: TraceId(),
                                                  spanId: SpanId(),
                                                  traceFlags: TraceFlags(),
                                                  traceState: TraceState())
    var isRecording: Bool = true
    var status: Status = .ok
    var name: String = Keys.iosSdk.rawValue

    var setAttributeCalled = false
    var setAttributeKey: String?
    var setAttributeValue: AttributeValue?

    func setAttribute(key: String, value: AttributeValue?) {
        setAttributeCalled = true
        setAttributeKey = key
        setAttributeValue = value
        recordedAttributes[key] = value
    }

    func addEvent(name: String) {}
    func addEvent(name: String, timestamp: Date) {}
    func addEvent(name: String, attributes: [String: AttributeValue]) {}
    func addEvent(name: String, attributes: [String: AttributeValue], timestamp: Date) {}
    func end() {
        didEnd = true
    }
    func end(time: Date) {}

    var description: String { return "MockSpan" }

    static func == (lhs: MockSpan, rhs: MockSpan) -> Bool {
        return lhs.name == rhs.name
    }
}


class CoralogixExporterOptionsTests: XCTestCase {
    
    // Test initialization with required parameters
    func testInit() {
        // Arrange
        let coralogixDomain = CoralogixDomain.US2 // Example domain
        let userContext = UserContext(userId: "1234",
                                      userName: "Daffy Duck",
                                      userEmail: "daffy.duck@coralogix.com",
                                      userMetadata: ["age": "18", "profession" : "duck"]) 
        let environment = "development"
        let application = "TestApp"
        let version = "1.0"
        let publicKey = "publicKey"
        
        // Act
        let options = CoralogixExporterOptions(
            coralogixDomain: coralogixDomain,
            userContext: userContext,
            environment: environment,
            application: application,
            version: version,
            publicKey: publicKey
        )
        
        // Assert
        XCTAssertEqual(options.coralogixDomain, coralogixDomain)
        XCTAssertEqual(options.userContext, userContext)
        XCTAssertEqual(options.environment, environment)
        XCTAssertEqual(options.application, application)
        XCTAssertEqual(options.version, version)
        XCTAssertEqual(options.publicKey, publicKey)
    }
}
