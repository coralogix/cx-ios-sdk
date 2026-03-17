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

// MARK: - coerceToInt unit tests

final class CoerceToIntTests: XCTestCase {
    private var sut: CoralogixRum!

    override func setUp() {
        super.setUp()
        let opts = CoralogixExporterOptions(coralogixDomain: .US2,
                                            userContext: nil,
                                            environment: "test",
                                            application: "TestApp",
                                            version: "1.0",
                                            publicKey: "token",
                                            ignoreUrls: [],
                                            ignoreErrors: [],
                                            labels: [:],
                                            debug: false)
        sut = CoralogixRum(options: opts)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // NSNumber wrapping a true integer: preserved as-is
    func test_coerceToInt_nsNumberInteger_returnsValue() {
        XCTAssertEqual(sut.coerceToInt(NSNumber(value: 200)), 200)
        XCTAssertEqual(sut.coerceToInt(NSNumber(value: 404)), 404)
        XCTAssertEqual(sut.coerceToInt(NSNumber(value: 599)), 599)
    }

    // NSNumber with a fractional part: must be rejected (same as Double/String paths)
    func test_coerceToInt_nsNumberFractional_returnsNil() {
        XCTAssertNil(sut.coerceToInt(NSNumber(value: 200.5)),
                     "NSNumber(200.5) must be rejected — fractional values are not exact integers")
        XCTAssertNil(sut.coerceToInt(NSNumber(value: 404.1)))
    }

    // NSNumber out of representable Int range: must not trap and must return nil
    func test_coerceToInt_nsNumberOutOfIntRange_returnsNil() {
        // 1e20 > Int64.max; Int(exactly:) returns nil so no runtime trap occurs
        XCTAssertNil(sut.coerceToInt(NSNumber(value: 1e20)))
    }

    // NSNumber outside the 100...599 status-code window: filtered by range check
    func test_coerceToInt_nsNumberOutOfStatusRange_returnsNil() {
        XCTAssertNil(sut.coerceToInt(NSNumber(value: 99)))
        XCTAssertNil(sut.coerceToInt(NSNumber(value: 600)))
        XCTAssertNil(sut.coerceToInt(NSNumber(value: 0)))
    }

    // Sanity-check the other branches are unaffected
    func test_coerceToInt_otherTypes_behavesCorrectly() {
        XCTAssertEqual(sut.coerceToInt(200),    200)   // Int
        XCTAssertEqual(sut.coerceToInt(200.0),  200)   // Double exact
        XCTAssertNil(sut.coerceToInt(200.5))           // Double fractional
        XCTAssertEqual(sut.coerceToInt("201"),  201)   // String Int
        XCTAssertNil(sut.coerceToInt("200.5"))         // String fractional Double
        XCTAssertNil(sut.coerceToInt("abc"))           // String non-numeric
        XCTAssertNil(sut.coerceToInt(nil))             // nil
    }
}
