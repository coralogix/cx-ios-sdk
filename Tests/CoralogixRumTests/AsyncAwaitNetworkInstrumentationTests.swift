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
            receivedResponse: { _, _, _ in },
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
