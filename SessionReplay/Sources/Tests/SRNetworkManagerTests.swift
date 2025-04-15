//
//  NetworkManagerTests.swift
//  Coralogix-Tests
//
//  Created by Tomer Har Yoffi on 21/01/2025.
//

import XCTest
import CoralogixInternal
@testable import Session_Replay

final class SRNetworkManagerTests: XCTestCase {
    var networkManager: SRNetworkManager!
    var mockSession: MockURLSession!
    var mockCoralogix: MockCoralogix!
    
    override func setUp() {
        super.setUp()
        let mockCoralogix = MockCoralogix()
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
        let trackNumber = 1
        let subIndex = 1
        
        let mockSession = MockURLSession()
        networkManager = SRNetworkManager(session: mockSession)
        
        // Call the method under test
        let result = networkManager.send(testData, timestamp: timestamp, sessionId: sessionId, trackNumber: trackNumber, subIndex: subIndex)
        
        // Assert the result
        XCTAssertEqual(result, .success, "The send method should return .success for a valid request")
    }
    
    func testSend_Failure_InvalidEndPoint() {
        // Prepare test data
        let testData = Data("Test data".utf8)
        let timestamp = Date().timeIntervalSince1970
        let sessionId = "mockSessionId"
        let trackNumber = 1
        let subIndex = 1
        
        // Simulate missing endPoint
        networkManager.endPoint = nil
        
        // Call the method under test
        let result = networkManager.send(testData, timestamp: timestamp, sessionId: sessionId, trackNumber: trackNumber, subIndex: subIndex)
        
        // Assert the result
        XCTAssertEqual(result, .failure, "The send method should return .failure when endPoint is nil")
    }
    
    func testSend_Failure_InvalidJSON() {
        // Prepare test data
        let invalidData = Data() // Empty data
        let timestamp: TimeInterval = Date().timeIntervalSince1970
        let sessionId = "testSessionId"
        let trackNumber = 1
        let subIndex = 1
        
        // Call the method under test
        let result = networkManager.send(invalidData, timestamp: timestamp, sessionId: sessionId, trackNumber: trackNumber, subIndex: subIndex)
        
        // Assert the result
        XCTAssertEqual(result, .failure, "The send method should return .failure for invalid JSON.")
    }
    
    func testBuildMetadata_ReturnsCorrectValues() {
        // Arrange
        let builder = MetadataBuilder()
        
        let application = "TestApp"
        let sessionCreationTime: TimeInterval = Date().timeIntervalSince1970
        let timestamp: TimeInterval = Date().timeIntervalSince1970
        let sessionId = "testSession123"
        let dataSize = 1024
        let trackNumber = 1
        let subIndex = 2
        
        // Act
        let metadata = builder.buildMetadata(
            dataSize: dataSize,
            timestamp: timestamp,
            sessionId: sessionId,
            trackNumber: trackNumber,
            subIndex: subIndex,
            application: application,
            sessionCreationTime: sessionCreationTime
        )
        
        // Assert
        XCTAssertEqual(metadata[Keys.application.rawValue] as? String, application, "Application value is incorrect")
        XCTAssertEqual(metadata[Keys.segmentIndex.rawValue] as? Int, trackNumber, "Track number value is incorrect")
        XCTAssertEqual(metadata[Keys.segmentSize.rawValue] as? Int, dataSize, "Data size value is incorrect")
        XCTAssertEqual(metadata[Keys.segmentTimestamp.rawValue] as? Int, timestamp.milliseconds, "Timestamp value is incorrect")
        XCTAssertEqual(metadata[Keys.keySessionCreationDate.rawValue] as? Int, sessionCreationTime.milliseconds, "Session creation timestamp is incorrect")
        XCTAssertEqual(metadata[Keys.keySessionId.rawValue] as? String, sessionId, "Session ID value is incorrect")
        XCTAssertEqual(metadata[Keys.subIndex.rawValue] as? Int, subIndex, "Sub-index value is incorrect")
    }
    
    func testBuildMetadata_ReturnsAllKeys() {
        // Arrange
        let builder = MetadataBuilder()
        
        let application = "TestApp"
        let sessionCreationTime: TimeInterval = Date().timeIntervalSince1970
        let timestamp: TimeInterval = Date().timeIntervalSince1970
        let sessionId = "testSession123"
        let dataSize = 1024
        let trackNumber = 1
        let subIndex = 2
        
        // Act
        let metadata = builder.buildMetadata(
            dataSize: dataSize,
            timestamp: timestamp,
            sessionId: sessionId,
            trackNumber: trackNumber,
            subIndex: subIndex,
            application: application,
            sessionCreationTime: sessionCreationTime
        )
        
        // Assert
        let expectedKeys: [String] = [
            Keys.application.rawValue,
            Keys.segmentIndex.rawValue,
            Keys.segmentSize.rawValue,
            Keys.segmentTimestamp.rawValue,
            Keys.keySessionCreationDate.rawValue,
            Keys.keySessionId.rawValue,
            Keys.subIndex.rawValue
        ]
        
        XCTAssertEqual(metadata.keys.sorted(), expectedKeys.sorted(), "Metadata keys are incorrect")
    }
}

class MockCoralogix: CoralogixInterface {
    // Properties to hold mock values
    var sessionID: String = "mockSessionID"
    var coralogixDomain: String = "https://mock-coralogix.com"
    var publicKey: String = "mockPublicKey"
    var application: String = "mockApplication"
    var sessionCreationTimestamp: TimeInterval = 1737453647.568056
    var debugMode: Bool = false
    var reportedErrors: [String] = []
    
    // Simulate getSessionID
    func getSessionID() -> String {
        return sessionID
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
}

public class MockURLSession: URLSessionProtocol {
    var request: URLRequest?
    var completionHandler: ((Data?, URLResponse?, Error?) -> Void)?
    
    public func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTaskProtocol {
        self.request = request
        self.completionHandler = completionHandler
        return MockURLSessionDataTask() {
            // Simulate a successful response
            let mockData = Data("Mock response".utf8) // Mock response data
            let mockResponse = HTTPURLResponse(url: request.url!,
                                               statusCode: 200,
                                               httpVersion: nil,
                                               headerFields: nil) // Mock HTTP response
            completionHandler(mockData, mockResponse, nil)
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
