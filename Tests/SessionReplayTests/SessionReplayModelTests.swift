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
    
    func testSessionIdValidity_whenEmpty_shouldReturnFalse() {
        let isValid = sessionReplayModel.isSessionIdValid()
        XCTAssertFalse(isValid)
    }
    
    func testSessionIdValidity_whenNonEmpty_shouldReturnTrue() {
        sessionReplayModel.sessionId = "abc-123"
        
        let isValid = sessionReplayModel.isSessionIdValid()
        XCTAssertTrue(isValid)
    }
    
    func testPrepareScreenshotIfNeeded_returnsScreenshotData_whenAllValid() {
        let mockWindow = MockWindow()
        sessionReplayModel.getKeyWindow = { mockWindow }
        sessionReplayModel.sessionReplayOptions = SessionReplayOptions(
            recordingType: .image,
            captureScale: 1.0,
            captureCompressionQuality: 0.9,
            maskText: nil,
            maskAllImages: false,
            creditCardPredicate: nil
        )
        
        let result = sessionReplayModel.prepareScreenshotIfNeeded(properties: nil)
        XCTAssertNotNil(result)
    }
    
    func testPrepareScreenshotIfNeeded_returnsNil_whenNoWindow() {
        sessionReplayModel.getKeyWindow = { nil }
        
        sessionReplayModel.sessionReplayOptions = SessionReplayOptions(
            recordingType: .image,
            captureScale: 1.0,
            captureCompressionQuality: 0.9,
            maskText: nil,
            maskAllImages: false,
            creditCardPredicate: nil
        )
        
        let result = sessionReplayModel.prepareScreenshotIfNeeded(properties: nil)
        XCTAssertNil(result)
    }
    
    func testPrepareScreenshotIfNeeded_returnsNil_whenOptionsInvalid() {
        let mockWindow = MockWindow()
        sessionReplayModel.getKeyWindow = { mockWindow }
        sessionReplayModel.sessionReplayOptions = nil // deliberately invalid
        let result = sessionReplayModel.prepareScreenshotIfNeeded(properties: nil)
        XCTAssertNil(result)
    }

    func testCaptureImage_whenSessionIdIsEmpty_doesNotProceed() {
        let mockSessionReplayModel = MockSessionReplayModel()
        mockSessionReplayModel.sessionId = ""
        
        mockSessionReplayModel.captureImage(properties: nil)
        
        XCTAssertFalse(mockSessionReplayModel.didCallPrepareScreenshot)
        XCTAssertFalse(mockSessionReplayModel.didCallSaveScreenshot)
    }
    
    func testCaptureImage_usesProvidedScreenshotData() {
        let mockSessionReplayModel = MockSessionReplayModel()
        mockSessionReplayModel.sessionId = "abc123"
        
        let data = "mock image".data(using: .utf8)!
        let props: [String: Any] = ["screenshotData": data]
        
        mockSessionReplayModel.captureImage(properties: props)
        
        XCTAssertFalse(mockSessionReplayModel.didCallPrepareScreenshot, "Should not call fallback screenshot")
        XCTAssertFalse(mockSessionReplayModel.didCallSaveScreenshot)
        XCTAssertEqual(mockSessionReplayModel.capturedData, data)
    }
    
    func testCaptureImage_fallsBackToPrepareScreenshotIfNoneProvided() {
        let model = MockSessionReplayModel2()
        model.sessionId = "abc123"
        
        model.captureImage(properties: nil)
        
        XCTAssertTrue(model.didCallPrepareScreenshot)
        XCTAssertTrue(model.didCallSaveScreenshot)
        XCTAssertEqual(model.passedScreenshotData, "mock image".data(using: .utf8))
    }
    
    func testCaptureImage_logsAndReturnsIfPrepareScreenshotFails() {
        class FailingScreenshotModel: MockSessionReplayModel2 {
            override func prepareScreenshotIfNeeded(properties: [String : Any]? = nil) -> Data? {
                didCallPrepareScreenshot = true
                return nil
            }
        }
        
        let model = FailingScreenshotModel()
        model.sessionId = "abc123"
        
        model.captureImage(properties: nil)
        
        XCTAssertTrue(model.didCallPrepareScreenshot)
        XCTAssertFalse(model.didCallSaveScreenshot)
    }
    
    func testUpdateSessionId_whenChanged_triggersClearAndDelete() {
        let mockSessionReplayModel = MockSessionReplayModel()
        mockSessionReplayModel.sessionId = "abc"
        
        mockSessionReplayModel.updateSessionId(with: "xyz")
        
        XCTAssertEqual(mockSessionReplayModel.sessionId, "xyz")
        XCTAssertTrue(mockSessionReplayModel.clearSessionReplayFolderCalled)
    }
    
    func testUpdateSessionId_whenUnchanged_doesNothing() {
        let mockSessionReplayModel = MockSessionReplayModel()
        mockSessionReplayModel.sessionId = "same"
        
        mockSessionReplayModel.updateSessionId(with: "same")
        
        XCTAssertEqual(mockSessionReplayModel.sessionId, "same")
        XCTAssertFalse(mockSessionReplayModel.clearSessionReplayFolderCalled)
    }
    
    func testPrepareScreenshotIfNeeded_dispatchesToMain_ifNotMainThread() {
        let expectation = XCTestExpectation(description: "captureImage called on main")
        let mockSessionReplayModel = MockSessionReplayModel()
        mockSessionReplayModel.expectation = expectation
        
        DispatchQueue.global().async {
            let result = mockSessionReplayModel.prepareScreenshotIfNeeded(properties: nil)
            XCTAssertNil(result)
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testSaveScreenshotToFileSystem_savesToCorrectPathAndCallsHandleCapturedData() {
        // Given
        let mockModel = MockSessionReplayModel()
        let sampleData = "dummy image".data(using: .utf8)!
        let sampleProperties: [String: Any] = ["source": "test"]
        
        // When
        mockModel.saveScreenshotToFileSystem(screenshotData: sampleData, properties: sampleProperties)
        
        // Then
        XCTAssertNotNil(mockModel.capturedFileURL, "Expected a valid file URL")
        XCTAssertEqual(mockModel.capturedData, sampleData, "Expected the data to be passed correctly")
        XCTAssertEqual(mockModel.capturedProperties?["source"] as? String, "test", "Expected properties to be passed correctly")
        
        // Confirm the file path is within the SessionReplay directory
        let fileURL = mockModel.capturedFileURL!.path
        XCTAssertTrue(fileURL.contains("/SessionReplay/mock_screenshot.jpg"), "Expected file URL to contain correct subpath")
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
        let segmentIndex = 2
        let page = 1
        sessionReplayModel.sessionId = mockSessionId
        
        let properties = [Keys.segmentIndex.rawValue: segmentIndex, Keys.page.rawValue: page]
        let result = sessionReplayModel.generateFileName(properties: properties)
        
        XCTAssertEqual(result, "\(mockSessionId)_\(page)_\(segmentIndex).jpg", "File name should match the expected format")
    }
    
    func testCompressAndSendData_withValidData_shouldReturnSuccess() {
        // Arrange
        let testData = "Test data for compression".data(using: .utf8)!
        let mockTimestamp: TimeInterval = 1234567890.0
        let mockNetworkManager = MockSRNetworkManager()
        let mockScreenshotId: String = "mockScreenshotId"
        sessionReplayModel = SessionReplayModel(networkManager: mockNetworkManager)
        
        let urlEntry = URLEntry(url: URL(string: "https://www.google.com")!,
                                timestamp: mockTimestamp,
                                screenshotId: mockScreenshotId,
                                screenshotIndex: 1,
                                page: "0",
                                screenshotData: testData,
                                point: CGPoint(x: 100.0, y: 100.0),
                                completion: nil)
        // Act
        let result = sessionReplayModel.compressAndSendData(data: testData, urlEntry: urlEntry)
        
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
        let invalidData = Data("".utf8) // Empty payload to test error handling
        let mockTimestamp: TimeInterval = 1234567890.0
        let mockScreenshotId: String = "mockScreenshotId"
        let urlEntry = URLEntry(url: URL(string: "https://www.google.com")!,
                                timestamp: mockTimestamp,
                                screenshotId: mockScreenshotId,
                                screenshotIndex: 1,
                                page: "0",
                                screenshotData: invalidData,
                                point: CGPoint(x: 100.0, y: 100.0),
                                completion: nil)

        // Act
        let result = sessionReplayModel.compressAndSendData(data: invalidData, urlEntry: urlEntry)
        
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
        let point = CGPoint(x: 10, y: 20)
        let properties: [String: Any] = [
            Keys.timestamp.rawValue: timestamp,
            Keys.screenshotId.rawValue: screenshotId,
            Keys.positionX.rawValue: CGFloat(10),
            Keys.positionY.rawValue: CGFloat(20)
        ]

        let mockURLManager = MockURLManager()
        let mockSessionReplayModel = MockSRModel()
        mockSessionReplayModel.urlManager = mockURLManager
        mockSessionReplayModel.sessionId = "mock-session"
        
        let expectation = self.expectation(description: "URLManager.addURL called")
        mockURLManager.expectation = expectation
        
        mockSessionReplayModel.handleCapturedData(fileURL: fileURL, data: data, properties: properties)
        
        waitForExpectations(timeout: 1.0)
        let entry = mockURLManager.addedURLs.first
        XCTAssertEqual(entry?.url, fileURL)
        XCTAssertEqual(entry?.timestamp, timestamp)
        XCTAssertEqual(entry?.screenshotId, screenshotId)
        XCTAssertEqual(entry?.screenshotData, data)
        XCTAssertEqual(entry?.point, point)
    }
}

class MockSRModel: SessionReplayModel {
    var compressCalled = false
    var passedData: Data?
    var passedTimestamp: TimeInterval?
    var passedScreenshotId: String?
    
    override func compressAndSendData(data: Data,
                                      urlEntry: URLEntry?) -> SessionReplayResultCode {
        compressCalled = true
        passedData = data
        passedTimestamp = urlEntry?.timestamp
        passedScreenshotId = urlEntry?.screenshotId
        return .success
    }
    
    override func updateSessionId(with sessionId: String) {
        // Can assert session ID update if needed
    }
}

class MockURLManager: URLManager {
    private(set) var addedURLs: [URLEntry] = []
    var expectation: XCTestExpectation?

    override func addURL(urlEntry: URLEntry) {
        addedURLs.append(urlEntry)
        expectation?.fulfill()
    }
}

final class MockSRNetworkManager: SRNetworkManager {
    var didSendData = false
    var sentChunks: [Data] = []
    
    override func send(_ data: Data,
                       urlEntry: URLEntry?,
                       sessionId: String,
                       subIndex: Int,
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
}

class MockSessionReplayModel: SessionReplayModel {
    var captureCalled = false
    var expectation: XCTestExpectation?
    var capturedFileURL: URL?
    var capturedData: Data?
    var capturedProperties: [String: Any]?
    var clearSessionReplayFolderCalled = false
    var didCallPrepareScreenshot = false
    var didCallSaveScreenshot = false
    var captureImageCallCount = 0

    override func clearSessionReplayFolder(fileManager: FileManager = .default) -> SessionReplayResultCode {
        clearSessionReplayFolderCalled = true
        return .success
    }
    
    override func captureImage(properties: [String : Any]? = nil) {
        captureImageCallCount += 1

        captureCalled = true
        capturedData = "mock image".data(using: .utf8)
        XCTAssertTrue(Thread.isMainThread, "captureImage should be called on the main thread")
        expectation?.fulfill()
    }
    
    override func handleCapturedData(
        fileURL: URL,
        data: Data,
        properties: [String : Any]?
    ) {
        capturedFileURL = fileURL
        capturedData = data
        capturedProperties = properties
    }

    override func generateFileName(properties: [String : Any]?) -> String {
        return "mock_screenshot.jpg"
    }
}

class MockSessionReplayModel2: SessionReplayModel {
    var didCallPrepareScreenshot = false
    var didCallSaveScreenshot = false
    var passedScreenshotData: Data?
    var passedProperties: [String: Any]?

    override func prepareScreenshotIfNeeded(properties: [String : Any]? = nil) -> Data? {
        didCallPrepareScreenshot = true
        return "mock image".data(using: .utf8)
    }

    override func saveScreenshotToFileSystem(screenshotData: Data, properties: [String : Any]?) {
        didCallSaveScreenshot = true
        passedScreenshotData = screenshotData
        passedProperties = properties
    }
}
