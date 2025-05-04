//
//  SessionReplayModelTests.swift
//  Session-Replay-Tests
//
//  Created by Tomer Har Yoffi on 23/01/2025.
//

import XCTest
import CoralogixInternal
@testable import SessionReplay


final class SessionReplayModelTests: XCTestCase {
    var sessionReplayModel: SessionReplayModel!
    var mockCoralogix: MockCoralogix!
    var tempDirectoryURL: URL!
    var mockFileManager: MockFileManager!
    
    override func setUpWithError() throws {
        super.setUp()
        sessionReplayModel = SessionReplayModel()
        mockCoralogix = MockCoralogix()
        mockFileManager = MockFileManager()

        // Initialize the SRNetworkManager
        SdkManager.shared.register(coralogixInterface: mockCoralogix)
        
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        // Create temporary directory
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }
    
    override func tearDownWithError() throws {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        sessionReplayModel = nil
        tempDirectoryURL = nil
        mockCoralogix = nil
        mockFileManager = nil
        super.tearDown()
    }
    
    func testCaptureImage() {
        // Arrange
        //            let expectation = self.expectation(description: "testCaptureImage")
        //
        //            mockWindow.shouldReturnScreenshotData = true
        //
        //            sut.handleCapturedData = { fileURL, data, timestamp in
        //                XCTAssertNotNil(data, "Screenshot data should not be nil")
        //                XCTAssertTrue(fileURL.absoluteString.contains("screenshot_"), "File name should contain 'screenshot_' prefix")
        //                expectation.fulfill()
        //            }
        //
        //            // Act
        //            sut.captureImage()
        //
        //            // Assert
        //            waitForExpectations(timeout: 1.0)
    }
    
    func testUpdateSessionId_SameSession_IncrementTrack() {
        // Given
        sessionReplayModel.sessionId = "oldSession"
        sessionReplayModel.screenshotManager.screenshotCount = 1
        
        // When
        sessionReplayModel.updateSessionId(with: "oldSession")
        
        // Then
        XCTAssertEqual(sessionReplayModel.screenshotManager.screenshotCount, 1)
        XCTAssertEqual(sessionReplayModel.sessionId, "oldSession")
        XCTAssertEqual(mockFileManager.clearSessionReplayFolderCallCount, 0, "Should not clear folder when session ID is unchanged")
    }
    
    func testUpdateSessionId_NewSession_ResetTrackAndClearFolder() {
        // Given
        sessionReplayModel.sessionId = "oldSession"
        sessionReplayModel.screenshotManager.screenshotCount = 1
        
        // When
        sessionReplayModel.updateSessionId(with: "newSession")
        
        // Then
        XCTAssertEqual(sessionReplayModel.screenshotManager.screenshotCount, 0)
        XCTAssertEqual(sessionReplayModel.sessionId, "newSession")
    }
    
    func testClearSessionReplayFolder_NoDocumentsDirectory_ReturnsFailure() {
        // Given
        mockFileManager.createdPaths.removeAll()
        
        // When
        let result = sessionReplayModel.clearSessionReplayFolder(fileManager: mockFileManager)
        
        // Then
        XCTAssertEqual(result, .failure)
        XCTAssertEqual(mockFileManager.createdPaths.count, 0)
        XCTAssertEqual(mockFileManager.removeItemCallCount, 0)
    }
    
    func testClearSessionReplayFolder_NoItemsInFolder() {
        // Given
        mockFileManager.createdPaths.append("file:///tmp/")
        
        // When
        let result = sessionReplayModel.clearSessionReplayFolder(fileManager: mockFileManager)
        
        // Then
        XCTAssertEqual(result, .failure)
        XCTAssertEqual(mockFileManager.contentsOfDirectoryCallCount, 1)
        XCTAssertEqual(mockFileManager.removeItemCallCount, 0)
    }
    
    func testClearSessionReplayFolder_ItemsInFolder_RemovesAll_ReturnsSuccess() {
        // Given
        mockFileManager.createdPaths.append("file:///tmp/")
        mockFileManager.contentsOfDirectoryResult = [URL(string: "file:///tmp/SessionReplay/file1.txt")!, URL(string: "file:///tmp/SessionReplay/file2.txt")!]
        
        // When
        let result = sessionReplayModel.clearSessionReplayFolder(fileManager: mockFileManager)
        
        // Then
        XCTAssertEqual(result, .success)
        XCTAssertEqual(mockFileManager.contentsOfDirectoryCallCount, 1)
        XCTAssertEqual(mockFileManager.removeItemCallCount, 2) // Two items removed
    }
    
    func testClearSessionReplayFolder_FailsToRemoveItem_ReturnsFailure() {
        // Given
        mockFileManager.createdPaths.append("file:///tmp/")
        mockFileManager.contentsOfDirectoryResult = [URL(string: "file:///tmp/SessionReplay/file1.txt")!]
        mockFileManager.shouldThrowErrorOnRemove = true
        
        // When
        let result = sessionReplayModel.clearSessionReplayFolder(fileManager: mockFileManager)
        
        // Then
        XCTAssertEqual(result, .failure)
        XCTAssertEqual(mockFileManager.contentsOfDirectoryCallCount, 1)
        XCTAssertEqual(mockFileManager.removeItemCallCount, 1)
    }
    
    func testCreateSessionReplayFolder_whenFolderDoesNotExist_shouldCreateFolderAndReturnSuccess() {
        // Given
        mockFileManager.createdPaths.removeAll()
                
        // When
        let result = sessionReplayModel.createSessionReplayFolder(fileManager: mockFileManager)
                
        // Then
        XCTAssertEqual(result, .success)
        XCTAssertEqual(mockFileManager.createDirectoryCallCount, 1)
    }
    
    func testCreateSessionReplayFolder_FolderDoesNotExist_CreatesFolder_ReturnsSuccess() {
        // Given
        mockFileManager.existingPaths.removeAll()
        mockFileManager.existingPaths.insert("/tmp")
        // When
        let result = sessionReplayModel.createSessionReplayFolder(fileManager: mockFileManager)
        
        // Then
        XCTAssertEqual(result, .success)
        XCTAssertEqual(mockFileManager.createDirectoryCallCount, 1)
    }

    func testCalculateSubIndex_withMultipleChunks_shouldReturnCurrentIndex() {
        // Arrange
        let chunkCount = 5
        let currentIndex = 2
        
        // Act
        let result = sessionReplayModel.calculateSubIndex(chunkCount: chunkCount, currentIndex: currentIndex)
        
        // Assert
        XCTAssertEqual(result, currentIndex, "Expected calculateSubIndex to return currentIndex when chunkCount > 1")
    }
    
    func testCalculateSubIndex_withSingleChunk_shouldReturnNegativeOne() {
        // Arrange
        let chunkCount = 1
        let currentIndex = 0
        
        // Act
        let result = sessionReplayModel.calculateSubIndex(chunkCount: chunkCount, currentIndex: currentIndex)
        
        // Assert
        XCTAssertEqual(result, -1, "Expected calculateSubIndex to return -1 when chunkCount <= 1")
    }
    
    func testCalculateSubIndex_withNoChunks_shouldReturnNegativeOne() {
        // Arrange
        let chunkCount = 0
        let currentIndex = 0
        
        // Act
        let result = sessionReplayModel.calculateSubIndex(chunkCount: chunkCount, currentIndex: currentIndex)
        
        // Assert
        XCTAssertEqual(result, -1, "Expected calculateSubIndex to return -1 when chunkCount == 0")
    }
    
    
    func testGetTimestamp_withValidProperties_shouldReturnTimestamp() {
        // Arrange
        let expectedTimestamp: TimeInterval = 1234567890.0
        let properties: [String: Any] = [Keys.timestamp.rawValue: expectedTimestamp]
        
        // Act
        let result = sessionReplayModel.getTimestamp(from: properties)
        
        // Assert
        XCTAssertEqual(result, expectedTimestamp, "Expected getTimestamp to return the timestamp from properties")
    }
    
    func testGetTimestamp_withMissingTimestamp_shouldReturnCurrentTime() {
        // Arrange
        let properties: [String: Any] = [:]
        let expectedTime = Date().timeIntervalSince1970 * 1000
        
        // Act
        let result = sessionReplayModel.getTimestamp(from: properties)
        
        // Assert
        XCTAssert(abs(result - expectedTime) < 1000, "Expected getTimestamp to return the current timestamp when none is provided")
    }
    
    func testGetTimestamp_withNilProperties_shouldReturnCurrentTime() {
        // Arrange
        let expectedTime = Date().timeIntervalSince1970 * 1000
        
        // Act
        let result = sessionReplayModel.getTimestamp(from: nil)
        
        // Assert
        XCTAssert(abs(result - expectedTime) < 1000, "Expected getTimestamp to return the current timestamp when properties is nil")
    }
    
    func testIsValidSessionReplayOptions_withValidOptions_shouldReturnTrue() {
        // Arrange
        let options = SessionReplayOptions(captureScale: 1.0, captureCompressionQuality: 0.8)
        
        // Act
        let result = sessionReplayModel.isValidSessionReplayOptions(options)
        
        // Assert
        XCTAssertTrue(result, "Expected isValidSessionReplayOptions to return true for valid options")
    }
    
    func testIsValidSessionReplayOptions_withInvalidCaptureScale_shouldReturnFalse() {
        // Arrange
        let options = SessionReplayOptions(captureScale: 0.0, captureCompressionQuality: 0.8)
        
        // Act
        let result = sessionReplayModel.isValidSessionReplayOptions(options)
        
        // Assert
        XCTAssertFalse(result, "Expected isValidSessionReplayOptions to return false for invalid captureScale")
    }
    
    func testIsValidSessionReplayOptions_withInvalidCompressionQuality_shouldReturnFalse() {
        // Arrange
        let options = SessionReplayOptions(captureScale: 1.0, captureCompressionQuality: 0.0)
        
        // Act
        let result = sessionReplayModel.isValidSessionReplayOptions(options)
        
        // Assert
        XCTAssertFalse(result, "Expected isValidSessionReplayOptions to return false for invalid captureCompressionQuality")
    }
    
    func testGenerateFileName_shouldReturnCorrectFileName() {
        // Arrange
        let mockSessionId = "testSessionId"
        let mockSreenshotNumber = 42
        sessionReplayModel.sessionId = mockSessionId
        sessionReplayModel.screenshotManager.screenshotCount = mockSreenshotNumber
        
        // Act
        let result = sessionReplayModel.generateFileName()
        
        // Assert
        XCTAssertEqual(result, "\(mockSessionId)_\(mockSreenshotNumber).jpg", "File name should match the expected format")
    }
    
    func testCompressAndSendData_withValidData_shouldReturnSuccess() {
        // Arrange
        let testData = "Test data for compression".data(using: .utf8)!
        let mockTimestamp: TimeInterval = 1234567890.0
        let mockNetworkManager = MockSRNetworkManager()
        let mockScreenshotId: String = "mockScreenshotId"
        sessionReplayModel = SessionReplayModel(networkManager: mockNetworkManager)
        // Act
        let result = sessionReplayModel.compressAndSendData(data: testData,
                                                            timestamp: mockTimestamp,
                                                            screenshotId: mockScreenshotId)
        
        // Assert
        XCTAssertEqual(result, .success, "Expected to return .success when compression and send succeed")
        XCTAssertTrue(mockNetworkManager.didSendData, "Expected srNetworkManager.send to be called")
        XCTAssertEqual(mockNetworkManager.sentChunks.count, 1, "Expected one chunk to be sent")
        XCTAssertNotNil(mockNetworkManager.sentChunks.first, "Sent chunk should not be nil")
        XCTAssertNotNil(testData.gzipCompressed()?.first, "Compressed data should not be nil")
        if let sentChunk = mockNetworkManager.sentChunks.first, let compressedChunk = testData.gzipCompressed()?.first {
            XCTAssertEqual(sentChunk, compressedChunk, "Sent chunk should match the compressed data")
        }
    }
    
    func testCompressAndSendData_withInvalidData_shouldReturnFailure() {
        // Arrange
        let invalidData = Data("".utf8) // Explicitly non-compressible payload
        let mockTimestamp: TimeInterval = 1234567890.0
        let mockScreenshotId: String = "mockScreenshotId"

        // Act
        let result = sessionReplayModel.compressAndSendData(data: invalidData,
                                                            timestamp: mockTimestamp,
                                                            screenshotId: mockScreenshotId)
        
        // Assert
        XCTAssertEqual(result, .failure, "Expected to return .failure when compression fails")
    }
    
    func testSaveImageToDocumentIfDebug_whenDebugMode_shouldCallSaveImageToDocument() {
        // Arrange
        let fileURL = tempDirectoryURL.appendingPathComponent("test_image.png")
        let testData = "Test image data".data(using: .utf8)!
        
        mockCoralogix.debugMode = true
        // Act
        let result = sessionReplayModel.saveImageToDocumentIfDebug(fileURL: fileURL, data: testData)
        
        // Assert
        XCTAssertEqual(result, .success, "Result should be .success when saving valid data")
    }
    
    func testSaveImageToDocumentIfDebug_whenDebugMode_shouldNotCallSaveImageToDocument() {
        // Arrange
        let fileURL = tempDirectoryURL.appendingPathComponent("test_image.png")
        let testData = "Test image data".data(using: .utf8)!
        
        mockCoralogix.debugMode = false
        // Act
        let result = sessionReplayModel.saveImageToDocumentIfDebug(fileURL: fileURL, data: testData)
        
        // Assert
        XCTAssertEqual(result, .failure, "Result should be .failure when debug mode is off")
    }
    
    func testSaveImageToDocument_withValidData_shouldSaveFile() {
        // Arrange
        let fileURL = tempDirectoryURL.appendingPathComponent("test_image.png")
        let testData = "Test image data".data(using: .utf8)!
        
        // Act
        let result = sessionReplayModel.saveImageToDocument(fileURL: fileURL, data: testData)
        
        // Assert
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "File should exist at the specified path")
        let savedData = try? Data(contentsOf: fileURL)
        XCTAssertEqual(savedData, testData, "Saved data should match the input data")
        XCTAssertEqual(result, .success, "Result should be .success when saving valid data")
    }
    
    func testSaveImageToDocument_withInvalidPath_shouldLogError() {
        // Arrange
        let invalidFileURL = URL(fileURLWithPath: "/invalid_path/test_image.png")
        let testData = "Test image data".data(using: .utf8)!
        
        // Act
        let result = sessionReplayModel.saveImageToDocument(fileURL: invalidFileURL, data: testData)
        
        // Assert
        XCTAssertEqual(result, .failure, "Result should be .failure when saving to an invalid path")
    }
    
    func testHandleCapturedData_ShouldCallAddURLAndCompress() {
        let fileURL = URL(string: "file:///mockfile.png")!
        let data = Data("mock".utf8)
        let timestamp = Date().timeIntervalSince1970
        let screenshotId = "mock-screenshot-id"
        let properties: [String: Any] = [
            Keys.timestamp.rawValue: timestamp,
            Keys.screenshotId.rawValue: screenshotId,
            "click_point": ["x": 20, "y": 30]
        ]
        
        let mockURLManager = MockURLManager()
        let mockSessionReplayModel = MockSRModel()
        mockSessionReplayModel.urlManager = mockURLManager
        mockSessionReplayModel.sessionId = "mock-session"
        
        let expectation = self.expectation(description: "Wait for async addURL completion")
        
        mockSessionReplayModel.handleCapturedData(fileURL: fileURL, data: data, properties: properties)
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            // Simulate completion
            mockURLManager.completion?(true, timestamp, screenshotId)
            expectation.fulfill()
        }
        
        // Assert
        waitForExpectations(timeout: 1.0)
        
        XCTAssertTrue(mockURLManager.addURLCalled)
        XCTAssertEqual(mockURLManager.passedURL, fileURL)
        XCTAssertEqual(mockURLManager.passedTimestamp!, timestamp, accuracy: 0.1)
        
        XCTAssertTrue(mockSessionReplayModel.compressCalled)
        XCTAssertEqual(mockSessionReplayModel.passedData, data)
        XCTAssertEqual(mockSessionReplayModel.passedTimestamp!, timestamp, accuracy: 0.1)
    }
}

class MockSRModel: SessionReplayModel {
    var compressCalled = false
    var passedData: Data?
    var passedTimestamp: TimeInterval?
    var passedScreenshotId: String?
    
    override func compressAndSendData(data: Data,
                                      timestamp: TimeInterval,
                                      screenshotId: String) -> SessionReplayResultCode {
        compressCalled = true
        passedData = data
        passedTimestamp = timestamp
        passedScreenshotId = screenshotId
        return .success
    }
    
    override func updateSessionId(with sessionId: String) {
        // Can assert session ID update if needed
    }
}

class MockURLManager: URLManager {
    var addURLCalled = false
    var passedURL: URL?
    var passedTimestamp: TimeInterval?
    var passedScreenshotId: String?
    var completion: ((Bool, TimeInterval, String) -> Void)?
    
    override func addURL(_ url: URL,
                         timestamp: TimeInterval,
                         screenshotId: String,
                         completion: ((Bool, TimeInterval, String) -> Void)? = nil) {
        addURLCalled = true
        passedURL = url
        passedTimestamp = timestamp
        passedScreenshotId = screenshotId
        self.completion = completion
    }
}

final class MockSRNetworkManager: SRNetworkManager {
    var didSendData = false
    var sentChunks: [Data] = []
    
    override func send(_ data: Data,
                       timestamp: TimeInterval,
                       sessionId: String,
                       screenshotNumber: Int,
                       subIndex: Int,
                       screenshotId: String,
                       page: String,
                       completion: @escaping (SessionReplayResultCode) -> Void) {
        didSendData = true
        sentChunks.append(data)
        completion(.success)
    }
}

final class MockWindowScene: UIWindowScene {
    var mockWindows: [UIWindow] = []
    var mockActivationState: UIScene.ActivationState = .foregroundActive

    override var windows: [UIWindow] {
        return mockWindows
    }

    override var activationState: UIScene.ActivationState {
        return mockActivationState
    }
}

class MockWindow: UIWindow {
    private var mockIsKeyWindow: Bool = false

    override var isKeyWindow: Bool {
        return mockIsKeyWindow
    }

    func setAsKeyWindow(_ isKeyWindow: Bool) {
        self.mockIsKeyWindow = isKeyWindow
    }
}

class MockFileManager: FileManager {
    var existingPaths: Set<String> = []
    var createdPaths: [String] = []
    var contentsOfDirectoryResult: [URL] = []
    var shouldThrowErrorOnCreate = false
    var removeItemCallCount = 0
    var shouldThrowErrorOnRemove = false
    var createDirectoryCallCount = 0
    var contentsOfDirectoryCallCount = 0
    var clearSessionReplayFolderCallCount = 0
    
    override func fileExists(atPath path: String) -> Bool {
        return existingPaths.contains(path)
    }
    
    override func createDirectory(at url: URL,
                                  withIntermediateDirectories createIntermediates: Bool,
                                  attributes: [FileAttributeKey : Any]? = nil
    ) throws {
        createDirectoryCallCount += 1
        if shouldThrowErrorOnCreate {
            throw NSError(domain: "MockError", code: 1, userInfo: nil)
        }
        createdPaths.append(url.path)
    }
    
    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        return [URL(fileURLWithPath: "/mock/documents")]
    }
    
    override func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions) throws -> [URL] {
        contentsOfDirectoryCallCount += 1
        return contentsOfDirectoryResult
    }
    
    override func removeItem(at URL: URL) throws {
        removeItemCallCount += 1
        if shouldThrowErrorOnRemove {
            throw NSError(domain: "TestErrorDomain", code: 1, userInfo: nil)
        }
    }
    
    func clearSessionReplayFolder() -> SessionReplayResultCode {
        clearSessionReplayFolderCallCount += 1
        return .success
    }
}
