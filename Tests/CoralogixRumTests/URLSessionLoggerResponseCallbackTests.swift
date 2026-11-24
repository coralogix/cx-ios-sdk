//
//  URLSessionLoggerResponseCallbackTests.swift
//  CoralogixRumTests
//
//  `logResponse` calls `receivedResponse` and then `receivedResponseWithRequest`, as upstream
//  OpenTelemetry does, with the same body and span; only the second is given the request.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class URLSessionLoggerResponseCallbackTests: XCTestCase {

    private static let url = URL(string: "https://api.example.com/items?id=1")!
    private static let body = Data(#"{"id":1}"#.utf8)

    private struct Call {
        let name: String
        let body: Data?
        let spanId: String
        let requestUrl: URL?
    }

    private let lock = NSLock()
    private var calls: [Call] = []
    private var previousShared: URLSessionInstrumentation?

    override func setUp() {
        super.setUp()
        previousShared = URLSessionInstrumentation.shared
    }

    // Building an instance replaces the process-wide `shared` one, which later tests read.
    override func tearDown() {
        URLSessionInstrumentation.restoreSharedForTesting(previousShared)
        previousShared = nil
        super.tearDown()
    }

    private func record(_ name: String, _ data: DataOrFile?, _ span: any Span, _ request: URLRequest?) {
        lock.lock()
        calls.append(Call(name: name,
                          body: NetworkCaptureRule.responseData(from: data),
                          spanId: span.context.spanId.hexString,
                          requestUrl: request?.url))
        lock.unlock()
    }

    func test_logResponse_callsBothCallbacksInUpstreamOrder() throws {
        let configuration = URLSessionInstrumentationConfiguration(
            shouldInstrument: { _ in true },
            shouldInjectTracingHeaders: { _ in false },
            receivedResponse: { [weak self] _, data, span in
                self?.record("receivedResponse", data, span, nil)
            },
            receivedResponseWithRequest: { [weak self] _, data, span, request in
                self?.record("receivedResponseWithRequest", data, span, request)
            },
            delegateClassesToInstrument: [],
            // A provider of its own, so the ended span never reaches an exporter another test installed.
            tracer: TracerProviderSdk().get(instrumentationName: "URLSessionLoggerResponseCallbackTests")
        )
        let instrumentation = URLSessionInstrumentation(configuration: configuration)
        let taskId = UUID().uuidString
        let request = URLRequest(url: Self.url)
        instrumentation.storeRequest(request, forTaskId: taskId)
        URLSessionLogger.processAndLogRequest(request,
                                              sessionTaskId: taskId,
                                              instrumentation: instrumentation,
                                              shouldInjectHeaders: false)
        let response = try XCTUnwrap(HTTPURLResponse(url: Self.url, statusCode: 200,
                                                     httpVersion: nil, headerFields: nil))

        URLSessionLogger.logResponse(response, dataOrFile: Self.body,
                                     instrumentation: instrumentation, sessionTaskId: taskId)

        lock.lock()
        let recorded = calls
        lock.unlock()
        XCTAssertEqual(recorded.map(\.name), ["receivedResponse", "receivedResponseWithRequest"])
        XCTAssertEqual(recorded.map(\.body), [Self.body, Self.body])
        XCTAssertEqual(Set(recorded.map(\.spanId)).count, 1, "both callbacks must get the same span")
        XCTAssertEqual(recorded.last?.requestUrl, Self.url)
    }
}
