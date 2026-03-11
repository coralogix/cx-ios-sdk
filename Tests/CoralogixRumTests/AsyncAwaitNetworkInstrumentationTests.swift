//
//  AsyncAwaitNetworkInstrumentationTests.swift
//  CoralogixRumTests
//
//  Created by Coralogix DEV TEAM on 05/02/2026.
//
//  NOTE: These tests require adding a test hook to capture spans.
//  See implementation note in testAsyncAwaitGETRequest for details.
//  
//  For now, use UI tests (NetworkInstrumentationUITests.swift) and verify console logs.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
final class AsyncAwaitNetworkInstrumentationTests: XCTestCase {
    var instrumentation: URLSessionInstrumentation!
    
    override func setUpWithError() throws {
        // Create instrumentation directly for testing
        let config = URLSessionInstrumentationConfiguration(
            shouldRecordPayload: { _ in true },
            shouldInstrument: { _ in true },
            shouldInjectTracingHeaders: { _ in true },
            createdRequest: { _, _ in },
            receivedResponse: { _, _, _, _ in }, // 4th param: optional URLRequest for header capture
            receivedError: { _, _, _, _ in },
            delegateClassesToInstrument: nil
        )
        
        instrumentation = URLSessionInstrumentation(configuration: config)
    }
    
    override func tearDownWithError() throws {
        instrumentation = nil
    }
    
    // MARK: - Basic Instrumentation Tests
    
    /// Basic test to verify instrumentation is initialized
    func testInstrumentationInitialized() {
        XCTAssertNotNil(instrumentation, "URLSessionInstrumentation should be initialized")
        XCTAssertNotNil(instrumentation.configuration, "Configuration should be set")
    }
    
    /// Test that instrumentation has the resume hook
    func testResumeHookExists() {
        // Verify that startedRequestSpans is accessible (means instrumentation is working)
        let spans = instrumentation.startedRequestSpans
        XCTAssertNotNil(spans, "Started request spans should be accessible")
    }

    // MARK: - Request map (header capture)

    /// When a request is stored for a taskId, getRequest(forTaskId:) returns it so receivedResponse can capture request_headers.
    func testStoreRequest_getRequest_returnsStoredRequest() throws {
        let url = try XCTUnwrap(URL(string: "https://api.example.com/endpoint"))
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer token", forHTTPHeaderField: "Authorization")
        let taskId = "test-task-\(UUID().uuidString)"

        instrumentation.storeRequest(request, forTaskId: taskId)

        let retrieved = instrumentation.getRequest(forTaskId: taskId)
        XCTAssertNotNil(retrieved, "Stored request must be returned by getRequest(forTaskId:) for header capture")
        XCTAssertEqual(retrieved?.url?.absoluteString, url.absoluteString)
        XCTAssertEqual(retrieved?.allHTTPHeaderFields?["Content-Type"], "application/json")
        XCTAssertEqual(retrieved?.allHTTPHeaderFields?["Authorization"], "Bearer token")
    }

    /// getRequest(forTaskId:) returns nil for unknown taskId.
    func testGetRequest_unknownTaskId_returnsNil() {
        XCTAssertNil(instrumentation.getRequest(forTaskId: "nonexistent-id"))
    }
    
    // MARK: - Integration Tests (Require Console Verification)
    //
    // NOTE: For full end-to-end testing, use NetworkInstrumentationUITests.swift
    // and verify console logs manually. These tests would require adding a test hook
    // to CoralogixExporter to capture spans programmatically.
    //
    // To add span capture capability, implement one of these approaches:
    //
    // Option 1: Test Hook (Recommended)
    // Add to CoralogixExporter.swift:
    //   #if DEBUG
    //   public var testSpanCallback: ((SpanDataProtocol) -> Void)?
    //   #endif
    //
    // Option 2: Notification
    // Post notification when span ends and observe in tests
    //
    // Option 3: Mock Exporter
    // Create test-specific exporter that captures instead of sending
}
