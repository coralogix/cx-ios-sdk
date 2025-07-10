//
//  NetworkManagerTests.swift
//  Coralogix-Tests
//
//  Created by Tomer Har Yoffi on 21/01/2025.
//

import XCTest
import CoralogixInternal
@testable import SessionReplay

final class SRNetworkManagerTests: XCTestCase {
    var networkManager: SRNetworkManager!
    var mockSession: MockURLSession!
    var mockCoralogix: MockCoralogix!
    
    override func setUp() {
        super.setUp()
        mockCoralogix = MockCoralogix()
        // Initialize the SRNetworkManager
        SdkManager.shared.register(coralogixInterface: mockCoralogix)
        networkManager = SRNetworkManager()
    }
    
    override func tearDown() {
        networkManager = nil
        mockCoralogix = nil
        mockSession = nil
        super.tearDown()
    }
    
    func testInit_Success() {
        // Mocked expected values
        let expectedDomain = "https://mock-coralogix.com"
        let expectedPath = Global.sessionReplayPath.rawValue
        let expectedPublicKey = "mockPublicKey"
        let expectedApplication = "mockApplication"
        
        // Assert properties are correctly set
        XCTAssertEqual(networkManager.endPoint, "\(expectedDomain)\(expectedPath)", "EndPoint was not set correctly")
        XCTAssertEqual(networkManager.publicKey, expectedPublicKey, "PublicKey was not set correctly")
        XCTAssertEqual(networkManager.application, expectedApplication, "Application was not set correctly")
        XCTAssertNotNil(networkManager.sessionCreationTimestamp, "SessionCreationTimestamp was not set correctly")
    }
    
    func testSend_Success() {
        // Prepare test data
        let testData = Data("Test data".utf8)
        let timestamp = Date().timeIntervalSince1970
        let sessionId = "mockSessionId"
        let segmentIndex = 1
        let subIndex = 1
        let screenshotId = UUID().uuidString.lowercased()
        let page: String = "0"
        mockSession = MockURLSession()
        networkManager = SRNetworkManager(session: mockSession)
        networkManager.proxyUrl = nil
        
        let urlEntry = URLEntry(url: URL(string: "https://www.google.com")!,
                                timestamp: timestamp,
                                screenshotId: screenshotId,
                                segmentIndex: segmentIndex,
                                page: page,
                                screenshotData: testData,
                                point: CGPoint(x: 100.0, y: 100.0),
                                completion: nil)
                                       
        // Call the method under test
        networkManager.send(testData,
                            urlEntry: urlEntry,
                            sessionId: sessionId,
                            subIndex: subIndex) { result in
            // Verify request was created and sent
            XCTAssertNotNil(self.mockSession.request, "No request was created")
            
            // Verify request has correct URL
            XCTAssertEqual(self.mockSession.request?.url?.absoluteString, self.networkManager.endPoint, "Request URL doesn't match endpoint")
            
            // Verify request method is POST
            XCTAssertEqual(self.mockSession.request?.httpMethod, "POST", "Request method should be POST")
            
            // Verify request contains data
            XCTAssertNotNil(self.mockSession.request?.httpBody, "Request body is nil")
        }
    }
    
    func testSend_Failure_InvalidEndPoint() {
        // Prepare test data
        let testData = Data("Test data".utf8)
        let timestamp = Date().timeIntervalSince1970
        let sessionId = "mockSessionId"
        let segmentIndex = 1
        let subIndex = 1
        let screenshotId = UUID().uuidString.lowercased()
        let page: String = "0"

        // Simulate missing endPoint
        networkManager.endPoint = nil
        
        let urlEntry = URLEntry(url: URL(string: "https://www.google.com")!,
                                timestamp: timestamp,
                                screenshotId: screenshotId,
                                segmentIndex: segmentIndex,
                                page: page,
                                screenshotData: testData,
                                point: CGPoint(x: 100.0, y: 100.0),
                                completion: nil)
        
        // Call the method under test
        networkManager.send(testData,
                            urlEntry: urlEntry,
                            sessionId: sessionId,
                            subIndex: subIndex) { result in
            // Assert the result
            XCTAssertEqual(result, .failure, "The send method should return .failure when endPoint is nil")
        }
    }
    
    func testSend_Failure_InvalidJSON() {
        // Prepare test data
        let invalidData = Data() // Empty data
        let timestamp: TimeInterval = Date().timeIntervalSince1970
        let sessionId = "testSessionId"
        let segmentIndex = 1
        let subIndex = 1
        let screenshotId = UUID().uuidString.lowercased()
        let page: String = "0"

        let urlEntry = URLEntry(url: URL(string: "https://www.google.com")!,
                                timestamp: timestamp,
                                screenshotId: screenshotId,
                                segmentIndex: segmentIndex,
                                page: page,
                                screenshotData: invalidData,
                                point: CGPoint(x: 100.0, y: 100.0),
                                completion: nil)
        
        mockSession = MockURLSession()
        mockSession.shouldReturnError = true
        networkManager = SRNetworkManager(session: mockSession)
        
        // Call the method under test
        networkManager.send(invalidData,
                            urlEntry: urlEntry,
                            sessionId: sessionId,
                            subIndex: subIndex) { result in
            
            // Assert the result
            XCTAssertEqual(result, .failure, "The send method should return .failure for invalid JSON.")
        }
    }
    
    func testBuildMetadata_ReturnsCorrectValues() {
        // Arrange
        let builder = MetadataBuilder()
        
        let application = "TestApp"
        let sessionCreationTime: TimeInterval = Date().timeIntervalSince1970
        let timestamp: TimeInterval = Date().timeIntervalSince1970
        let sessionId = "testSession123"
        let dataSize = 1024
        let segmentIndex = 1
        let subIndex = 2
        let screenshotId = UUID().uuidString.lowercased()
        let page = "0"

        // Act
        let metadata = builder.buildMetadata(
            dataSize: dataSize,
            timestamp: timestamp,
            sessionId: sessionId,
            segmentIndex: segmentIndex,
            subIndex: subIndex,
            application: application,
            sessionCreationTime: sessionCreationTime,
            screenshotId: screenshotId,
            page: page
        )
        
        // Assert
        XCTAssertEqual(metadata[Keys.application.rawValue] as? String, application, "Application value is incorrect")
        XCTAssertEqual(metadata[Keys.segmentIndex.rawValue] as? Int, segmentIndex, "Screenshot number value is incorrect")
        XCTAssertEqual(metadata[Keys.segmentSize.rawValue] as? Int, dataSize, "Data size value is incorrect")
        XCTAssertEqual(metadata[Keys.segmentTimestamp.rawValue] as? Int, timestamp.milliseconds, "Timestamp value is incorrect")
        XCTAssertEqual(metadata[Keys.keySessionCreationDate.rawValue] as? Int, sessionCreationTime.milliseconds, "Session creation timestamp is incorrect")
        XCTAssertEqual(metadata[Keys.keySessionId.rawValue] as? String, sessionId, "Session ID value is incorrect")
        XCTAssertEqual(metadata[Keys.subIndex.rawValue] as? Int, subIndex, "Sub-index value is incorrect")
        XCTAssertEqual(metadata[Keys.snapshotId.rawValue] as? String, screenshotId, "snapshotId value is incorrect")
        XCTAssertEqual(metadata[Keys.page.rawValue] as? String, page, "Page value is incorrect")
    }
    
    func testBuildMetadata_ReturnsAllKeys() {
        // Arrange
        let builder = MetadataBuilder()
        
        let application = "TestApp"
        let sessionCreationTime: TimeInterval = Date().timeIntervalSince1970
        let timestamp: TimeInterval = Date().timeIntervalSince1970
        let sessionId = "testSession123"
        let dataSize = 1024
        let segmentIndex = 1
        let subIndex = 2
        let screenshotId = UUID().uuidString.lowercased()
        let page = "0"

        // Act
        let metadata = builder.buildMetadata(
            dataSize: dataSize,
            timestamp: timestamp,
            sessionId: sessionId,
            segmentIndex: segmentIndex,
            subIndex: subIndex,
            application: application,
            sessionCreationTime: sessionCreationTime,
            screenshotId: screenshotId,
            page: page
        )
        
        // Assert
        let expectedKeys: [String] = [
            Keys.application.rawValue,
            Keys.segmentIndex.rawValue,
            Keys.segmentSize.rawValue,
            Keys.segmentTimestamp.rawValue,
            Keys.keySessionCreationDate.rawValue,
            Keys.keySessionId.rawValue,
            Keys.subIndex.rawValue,
            Keys.snapshotId.rawValue,
            Keys.page.rawValue
        ]
        
        XCTAssertEqual(metadata.keys.sorted(), expectedKeys.sorted(), "Metadata keys are incorrect")
    }
    
    func test_resolvedUrlString_withValidProxyUrl() {
        // Given
        let endPoint = "https://mock-coralogix.com/browser/alpha/sessionrecording"
        
        mockSession = MockURLSession()
        mockSession.shouldReturnError = true
        networkManager = SRNetworkManager(session: mockSession)
        networkManager.proxyUrl = "https://proxy.example.com"
        
        // When
        let result = networkManager.resolvedUrlString()
        
        // Then
        XCTAssertNotNil(result)
        
        guard let urlString = result,
              let components = URLComponents(string: urlString),
              let queryItems = components.queryItems else {
            XCTFail("URL is invalid or missing query items")
            return
        }
        
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "proxy.example.com")
        
        let cxforwardItem = queryItems.first { $0.name == Keys.cxforward.rawValue }
        XCTAssertNotNil(cxforwardItem)
        XCTAssertEqual(cxforwardItem?.value, endPoint)
    }
     
     func test_resolvedUrlString_withEmptyProxyUrl() {
         // Given
         let endPoint = "https://mock-coralogix.com/browser/alpha/sessionrecording"
         
         mockSession = MockURLSession()
         mockSession.shouldReturnError = true
         networkManager = SRNetworkManager(session: mockSession)
         networkManager.proxyUrl = ""
         
         // When
         let result = networkManager.resolvedUrlString()
         
         // Then
         XCTAssertEqual(result, endPoint)
     }
     
     func test_resolvedUrlString_withNilProxyUrl() {
         // Given
         let endPoint = "https://mock-coralogix.com/browser/alpha/sessionrecording"
         
         mockSession = MockURLSession()
         mockSession.shouldReturnError = true
         networkManager = SRNetworkManager(session: mockSession)
         networkManager.proxyUrl = nil
         
         // When
         let result = networkManager.resolvedUrlString()

         // Then
         XCTAssertEqual(result, endPoint)
     }
}

class MockCoralogix: CoralogixInterface {
    // Properties to hold mock values
    var sessionID: String = "mockSessionID"
    var coralogixDomain: String = "https://mock-coralogix.com"
    var proxyUrl: String = "https://proxy.example.com"
    var publicKey: String = "mockPublicKey"
    var application: String = "mockApplication"
    var sessionCreationTimestamp: TimeInterval = 1737453647.568056
    var debugMode: Bool = false
    var idle: Bool = false
    var reportedErrors: [String] = []
    var periodicallyCaptureEventCalled = false
    
    func periodicallyCaptureEventTriggered() {
        periodicallyCaptureEventCalled = true
    }
    
    func hasSessionRecording(_ hasSessionRecording: Bool) {
        // update the coralogix sdk that there is a session recording to that session
    }
    
    // Simulate getSessionID
    func getSessionID() -> String {
        return sessionID
    }
    
    func getProxyUrl() -> String {
        return proxyUrl
    }
    
    // Simulate getCoralogixDomain
    func getCoralogixDomain() -> String {
        return coralogixDomain
    }
    
    // Simulate getPublicKey
    func getPublicKey() -> String {
        return publicKey
    }
    
    // Simulate getApplication
    func getApplication() -> String {
        return application
    }
    
    // Simulate getSessionCreationTimestamp
    func getSessionCreationTimestamp() -> TimeInterval {
        return sessionCreationTimestamp
    }
    
    // Simulate reportError
    func reportError(_ error: String) {
        reportedErrors.append(error)
    }
    
    // Simulate isDebug
    func isDebug() -> Bool {
        return debugMode
    }
    
    func isIdle() -> Bool {
        return idle
    }
}

public class MockURLSession: URLSessionProtocol {
    var request: URLRequest?
    var completionHandler: ((Data?, URLResponse?, Error?) -> Void)?

    public var shouldReturnError: Bool = false
    public var mockData: Data? = Data("Mock response".utf8)
    public var mockStatusCode: Int = 200
    public var mockError: Error? = NSError(domain: "MockError", code: 1, userInfo: nil)

    public func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTaskProtocol {
        self.request = request
        self.completionHandler = completionHandler
        
        
        return MockURLSessionDataTask() {
            
            if self.shouldReturnError {
                completionHandler(nil, nil, self.mockError)
            } else {
                let mockData = Data("Mock response".utf8)
                let mockResponse = HTTPURLResponse(url: request.url!,
                                                   statusCode: self.mockStatusCode,
                                                   httpVersion: nil,
                                                   headerFields: nil)
                completionHandler(mockData, mockResponse, nil)
            }
        }
    }
}

class MockURLSessionDataTask: URLSessionDataTaskProtocol {
    private let closure: () -> Void
    
    init(closure: @escaping () -> Void) {
        self.closure = closure
    }
    
    func resume() {
        closure()
    }
}
