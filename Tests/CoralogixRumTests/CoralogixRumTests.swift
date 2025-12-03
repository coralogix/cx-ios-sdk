import XCTest
import CoralogixInternal
@testable import Coralogix

final class CoralogixRumTests: XCTestCase {
    var options: CoralogixExporterOptions?
    private var notificationTokens: [NSObjectProtocol] = []
    
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
                                           sessionSampleRate: 100,
                                           debug: true)
    }
    
    override func tearDownWithError() throws {
        options = nil
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
        // Reset any globals your production code checks:
        CoralogixRum.isInitialized = false
        // If you introduced a "native" flag, reset it here too.
        
        // Drain any queued main-thread notifications between tests
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
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
                                           sessionSampleRate: 0,
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
        coralogixRum.set(labels: newLabel)
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
                                                    sessionSampleRate: 100,
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
                                                    sessionSampleRate: 100,
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
                                                sessionSampleRate: 100,
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
                                                    sessionSampleRate: 100,
                                                    debug: true)
        let coralogixRum = CoralogixRum(options: mockOptions, sessionManager: mockSessionManager)
        
        // Test with a valid session metadata
        XCTAssertNotNil(coralogixRum.getSessionCreationTimestamp())
    }
    
    func testHandleAppearStateIfNeededWhenStateIsNotifyOnAppearShouldCaptureEventAndSetSpanAttribute() {
        let coralogixRum = makeMockCoralogixRum()
        var mockSpan: any Span = MockSpan()
        
        // Arrange
        let view = CXView(state: .notifyOnAppear, name: "home")
        let mockSessionReplay =  MockSessionReplay()
        SdkManager.shared.register(sessionReplayInterface: mockSessionReplay)
        // Act
        coralogixRum.handleAppearStateIfNeeded(cxView: view, span: &mockSpan)
        
        // Assert
        XCTAssertNotNil(mockSessionReplay.captureEventCalledWith, "Expected SessionReplay.captureEvent to be invoked")
        XCTAssertNotNil(mockSessionReplay.captureEventCalledWith?[Keys.screenshotId.rawValue] as? String, "Expected screenshotId to be present in captured metadata")
        if let m = mockSpan as? MockSpan {
            XCTAssertTrue(m.setAttributeCalled)
            XCTAssertNotNil(m.setAttributeKey)
            XCTAssertNotNil(m.setAttributeValue)
        }
        SdkManager.shared.register(sessionReplayInterface: nil)
    }
    
    func testHandleAppearStateIfNeededWhenStateIsNotNotifyOnAppearShouldNotCaptureEvent() {
        let coralogixRum = makeMockCoralogixRum()
        var mockSpan: any Span = MockSpan()
        let mockSessionReplay =  MockSessionReplay()
        
        // Arrange
        let view = CXView(state: .notifyOnDisappear, name: "home")
        
        // Act
        SdkManager.shared.register(sessionReplayInterface: mockSessionReplay)
        coralogixRum.handleAppearStateIfNeeded(cxView: view, span: &mockSpan)
        
        // Assert
        XCTAssertNil(mockSessionReplay.captureEventCalledWith)
        if let m = mockSpan as? MockSpan {
            XCTAssertFalse(m.setAttributeCalled)
        }
    }
    
    func testHandleAppearStateIfNeededWhenSessionReplayIsNilShouldNotCrashOrCaptureEvent() {
        
        SdkManager.shared.register(sessionReplayInterface: nil)
        let coralogixRum = makeMockCoralogixRum()
        var mockSpan: any Span = MockSpan()
        let view = CXView(state: .notifyOnAppear, name: "home")
        
        // Act
        coralogixRum.handleAppearStateIfNeeded(cxView: view, span: &mockSpan)
        
        // Assert
        if let m = mockSpan as? MockSpan {
            XCTAssertFalse(m.setAttributeCalled)
        }
    }
    
    func testGetNavigationSpanShouldSetCorrectAttributes() {
        let coralogixRum = makeMockCoralogixRum()
        
        coralogixRum.tracerProvider = {
            return MockTracer()
        }
        
        if let mockSpan = coralogixRum.makeSpan(event: .navigation, source: .console, severity: .info) as? MockSpan {
            // Assert
            XCTAssertEqual(mockSpan.recordedAttributes[Keys.eventType.rawValue], .string(CoralogixEventType.navigation.rawValue))
            XCTAssertEqual(mockSpan.recordedAttributes[Keys.source.rawValue], .string(Keys.console.rawValue))
            XCTAssertEqual(mockSpan.recordedAttributes[Keys.severity.rawValue], .int(CoralogixLogSeverity.info.rawValue))
        }
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
                                                    sessionSampleRate: 100,
                                                    debug: true)
        let coralogixRum =  CoralogixRum(options: mockOptions)
        let cxView = CXView(state: .notifyOnAppear, name: "TestView")
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
                                                    sessionSampleRate: 100,
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
        let mockOptions = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp-iOS",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            sessionSampleRate: 100,
            debug: true
        )
        
        let coralogixRum = CoralogixRum(options: mockOptions)

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
        let span = coralogixRum.makeSpan(event: .userInteraction, source: .console, severity: .info)
        
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
        
    func testAddScreenshotIdAddsAttributeAndCapturesEvent() {
        // Arrange
        var span: any Span = MockSpan()
        let mockSessionReplay = MockSessionReplay()
        
        SdkManager.shared.register(sessionReplayInterface: mockSessionReplay)
        
        let coralogixRum = makeMockCoralogixRum()
        
        // Act
        coralogixRum.recordScreenshotForSpan(to: &span)
        
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
        let span = coralogixRum.makeSpan(event: .error, source: .console, severity: .error)
        guard let mockSpan = span as? MockSpan else {
            XCTFail("Expected span to be MockSpan")
            return
        }
        XCTAssertEqual(mockSpan.recordedAttributes[Keys.eventType.rawValue], .string(CoralogixEventType.error.rawValue))
        XCTAssertEqual(mockSpan.recordedAttributes[Keys.source.rawValue], .string(Keys.console.rawValue))
        XCTAssertEqual(mockSpan.recordedAttributes[Keys.severity.rawValue], .int(CoralogixLogSeverity.error.rawValue))
    }
    
    func testShouldReturnFalse_WhenURLContainsCoralogixDomain() {
        let request = URLRequest(url: URL(string: "https://ingress.us2.rum-ingress-coralogix.com")!)
        let mockOptions = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp-iOS",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            sessionSampleRate: 100,
            debug: true
        )
        
        let coralogixRum = CoralogixRum(options: mockOptions)
        let result = coralogixRum.shouldAddTraceParent(to: request, options: mockOptions)
        XCTAssertFalse(result)
    }
    
    func testShouldReturnFalse_WhenTraceParentInHeaderIsNil() {
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let mockOptions = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp-iOS",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            sessionSampleRate: 100,
            debug: true
        )
        
        let coralogixRum = CoralogixRum(options: mockOptions)
        let result = coralogixRum.shouldAddTraceParent(to: request, options: mockOptions)
        XCTAssertFalse(result)
    }
    
    func testShouldReturnFalse_WhenTracingIsDisabled() {
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let mockOptions = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp-iOS",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            sessionSampleRate: 100,
            traceParentInHeader: ["enable": false],
            debug: true
        )
        
        let coralogixRum = CoralogixRum(options: mockOptions)
        let result = coralogixRum.shouldAddTraceParent(to: request, options: mockOptions)
        XCTAssertFalse(result)
    }
    
    func testShouldReturnTrue_WhenAllowedUrlsContainsRequestURL() {
        let request = URLRequest(url: URL(string: "https://allowed.com/path")!)
        let mockOptions = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp-iOS",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            sessionSampleRate: 100,
            traceParentInHeader: ["enable": true,
                                  "options" : [
                                    "allowedTracingUrls": ["https://allowed.com/path"]]],
            debug: true
        )
        
        let coralogixRum = CoralogixRum(options: mockOptions)
        let result = coralogixRum.shouldAddTraceParent(to: request, options: mockOptions)
        XCTAssertTrue(result)
    }
    
    func testShouldReturnTrue_WhenRegexMatchesRequestURL() {
        let request = URLRequest(url: URL(string: "https://test.com/path")!)
        let mockOptions = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp-iOS",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            sessionSampleRate: 100,
            traceParentInHeader: ["enable": true,
                                  "options" : [
                                    "allowedTracingUrls": [".*test\\.com.*"]]],
            debug: true
        )
        
        // Mock Global.isHostMatchesRegexPattern for test environment if needed
        let coralogixRum = CoralogixRum(options: mockOptions)
        let result = coralogixRum.shouldAddTraceParent(to: request, options: mockOptions)
        XCTAssertTrue(result)
    }
    
    func testShouldReturnTrue_WhenNoAllowedUrlsDefined() {
        let request = URLRequest(url: URL(string: "https://random.com")!)
        let mockOptions = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp-iOS",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            sessionSampleRate: 100,
            traceParentInHeader: ["enable": true],
            debug: true
        )
        
        let coralogixRum = CoralogixRum(options: mockOptions)
        let result = coralogixRum.shouldAddTraceParent(to: request, options: mockOptions)
        XCTAssertTrue(result)
    }
    
    func testSetView() {
        let mockOptions = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp-iOS",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            sessionSampleRate: 100,
            traceParentInHeader: ["enable": true],
            debug: true
        )
        let coralogixRum = CoralogixRum(options: mockOptions)
        let expectation = XCTestExpectation(description: "Wait for async setView to complete")
        coralogixRum.setView(name: "TestView")
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            let visibleView = coralogixRum.coralogixExporter?.getViewManager().visibleView
            XCTAssertNotNil(visibleView)
            XCTAssertEqual(visibleView?.name, "TestView")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testSetupTracer_registersTracerWithCorrectExporter() {
        let mockOptions = CoralogixExporterOptions(
            coralogixDomain: .US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp-iOS",
            version: "1.0",
            publicKey: "token",
            ignoreUrls: [],
            ignoreErrors: [],
            sessionSampleRate: 100,
            traceParentInHeader: ["enable": true],
            debug: true
        )
        let mockSessionManager = SessionManager()
        let mockExporter = MockCoralogixExporter(options: mockOptions,
                                                 sessionManager: mockSessionManager,
                                                 networkManager: NetworkManager(),
                                                 viewManager: ViewManager(keyChain: nil),
                                                 metricsManager: MetricsManager())
        
        let coralogixRum = CoralogixRum(options: mockOptions)
        
        coralogixRum.coralogixExporter = mockExporter
        let tracer = OpenTelemetry.instance.tracerProvider.get(instrumentationName: "MyTestApp")
        XCTAssertNotNil(tracer)
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
            fpsSampleRate: 100,
            debug: true
        )
        
        let coralogixRum = CoralogixRum(options: mockOptions)
        return coralogixRum
    }
    
    func test_reportMobileVitalsMeasurement_whenNotInitialized_shouldNotCallHandle() {
        guard let options = self.options else {
            XCTFail("options must be CoralogixRumOptions")
            return
        }

        let mock = MockCoralogixRum(options: options, sdkFramework: .reactNative(version: "1.0"))
        MockCoralogixRum.isInitialized = false

        // When
        mock.reportMobileVitalsMeasurement(type: "fps", value: 58.9, units: "fps")

        // Then
        XCTAssertTrue(mock.capturedVitals.isEmpty)
    }
    
    func test_reportMobileVitalsMeasurement_whenNativeSDK_shouldNotCallHandle() {
        guard let options = self.options else {
            XCTFail("options must be CoralogixRumOptions")
            return
        }
        
        let mock = MockCoralogixRum(options: options, sdkFramework: .swift)
        MockCoralogixRum.isInitialized = true

        // When
        mock.reportMobileVitalsMeasurement(type: "fps", value: 58.9, units: "fps")

        // Then
        XCTAssertTrue(mock.capturedVitals.isEmpty)
    }
}

final class MockCoralogixRum: CoralogixRum {
    var capturedVitals: [String: Any] = [:]
    
    init(options: CoralogixExporterOptions, sdkFramework:  SdkFramework = .swift) {
        super.init(options: options, sdkFramework: sdkFramework)
        
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
    func registerMaskRegion(region: [String : Any]) {
        
    }
    
    func unregisterMaskRegion(id: String) {
        
    }
    
    func captureEvent(properties: [String : Any]?) -> Result<Void, CoralogixInternal.CaptureEventError> {
        captureEventCalledWith = properties
        return .success(())
    }
    
    var captureEventCalledWith: [String: Any]?
    
    func startRecording() {
        
    }
    
    func stopRecording() {
        
    }
    
    func update(sessionId: String) {
        
    }
    
    func isRecording() -> Bool {
        return true
    }
    
    func isInitialized() -> Bool {
        return true
    }
}

public final class MockSpan: Span {
    var didEnd = false
    public var kind: SpanKind = .internal
    var recordedAttributes: [String: AttributeValue] = [:]
    public var context: SpanContext = SpanContext.create(traceId: TraceId(),
                                                  spanId: SpanId(),
                                                  traceFlags: TraceFlags(),
                                                  traceState: TraceState())
    public var isRecording: Bool = true
    public var status: Status = .ok
    public var name: String = Keys.iosSdk.rawValue
    
    var setAttributeCalled = false
    var setAttributeKey: String?
    var setAttributeValue: AttributeValue?
    
    public func setAttribute(key: String, value: AttributeValue?) {
        setAttributeCalled = true
        setAttributeKey = key
        setAttributeValue = value
        recordedAttributes[key] = value
    }
    
    public func addEvent(name: String) {}
    public func addEvent(name: String, timestamp: Date) {}
    public func addEvent(name: String, attributes: [String: AttributeValue]) {}
    public func addEvent(name: String, attributes: [String: AttributeValue], timestamp: Date) {}
    public func end() {
        didEnd = true
    }
    public func end(time: Date) {}
    
    public var description: String { return "MockSpan" }
    
    public static func == (lhs: MockSpan, rhs: MockSpan) -> Bool {
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
