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
    
    func test_handleAppearStateIfNeeded_whenStateIsNotifyOnAppear_shouldCaptureEventAndSetSpanAttribute() {
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
        let mockSpan = MockSpan()

        // Arrange
        let view = CXView(state: .notifyOnAppear, name: "home")
        let timestamp: TimeInterval = 1234567890
        let mockSessionReplay =  MockSessionRepaly()
        SdkManager.shared.register(sessionReplayInterface: mockSessionReplay)
        // Act
        coralogixRum.handleAppearStateIfNeeded(cxView: view, span: mockSpan, timestamp: timestamp)
        
        // Assert
        XCTAssertEqual(mockSessionReplay.captureEventCalledWith?[Keys.timestamp.rawValue] as? TimeInterval, timestamp)
        XCTAssertNotNil(mockSessionReplay.captureEventCalledWith?[Keys.screenshotId.rawValue] as? String)
        
        XCTAssertTrue(mockSpan.setAttributeCalled)
        XCTAssertNotNil(mockSpan.setAttributeKey)
        XCTAssertNotNil(mockSpan.setAttributeValue)
    }
    
    func test_handleAppearStateIfNeeded_whenStateIsNotNotifyOnAppear_shouldNotCaptureEvent() {
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
        let mockSpan = MockSpan()
        let mockSessionReplay =  MockSessionRepaly()

        // Arrange
        let view = CXView(state: .notifyOnDisappear, name: "home")
        let timestamp: TimeInterval = 1234567890

        // Act
        coralogixRum.handleAppearStateIfNeeded(cxView: view, span: mockSpan, timestamp: timestamp)

        // Assert
        XCTAssertNil(mockSessionReplay.captureEventCalledWith)
        XCTAssertFalse(mockSpan.setAttributeCalled)
    }
    
    func test_handleAppearStateIfNeeded_whenSessionReplayIsNil_shouldNotCrashOrCaptureEvent() {
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
        let mockSpan = MockSpan()

        // Arrange
        let view = CXView(state: .notifyOnAppear, name: "home")
        let timestamp: TimeInterval = 1234567890
        
        // Act
        coralogixRum.handleAppearStateIfNeeded(cxView: view, span: mockSpan, timestamp: timestamp)
        
        // Assert
        XCTAssertFalse(mockSpan.setAttributeCalled)
    }
}

final class MockSessionRepaly: SessionReplayInterface {
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
    var kind: SpanKind = .internal
    var context: SpanContext = SpanContext.create(traceId: TraceId(),
                                                  spanId: SpanId(),
                                                  traceFlags: TraceFlags(),
                                                  traceState: TraceState())
    var isRecording: Bool = true
    var status: Status = .ok
    var name: String = "MockSpan"

    var setAttributeCalled = false
    var setAttributeKey: String?
    var setAttributeValue: AttributeValue?

    func setAttribute(key: String, value: AttributeValue?) {
        setAttributeCalled = true
        setAttributeKey = key
        setAttributeValue = value
    }

    func addEvent(name: String) {}
    func addEvent(name: String, timestamp: Date) {}
    func addEvent(name: String, attributes: [String: AttributeValue]) {}
    func addEvent(name: String, attributes: [String: AttributeValue], timestamp: Date) {}
    func end() {}
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
