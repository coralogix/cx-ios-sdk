//
//  NetworkResponseBodyCompletionRaceTests.swift
//  CoralogixRumTests
//
//  A delegate-driven task (React Native's RCTHTTPRequestHandler is one) is completed by SDK paths that
//  can run at the same time: the setState: fallback on CFNetwork's queue and the session delegate's
//  callbacks. Whichever path ends the span must also attach the buffered response body. These tests run
//  one path inside another's window and assert the span ends once, with the body — and that no body is
//  left behind in the store once its task is done.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

/// Data task whose outcome (`error` / `response`) the tests control. Every completion path reads the
/// outcome before it claims the task's span, so work armed with `runOnFirstOutcomeRead` runs a second
/// completion path inside the first one's window — deterministically, with no timing involved.
private final class InterleavingDataTask: URLSessionDataTask, @unchecked Sendable {
    private var stubResponse: URLResponse?
    private var stubError: Error?
    private var armedWork: (() -> Void)?

    /// URLSessionDataTask's only initializer is deprecated; reaching it through NSObject's avoids the
    /// deprecation warning without changing what runs.
    static func make(response: URLResponse, error: Error? = nil) -> InterleavingDataTask? {
        let task = (self as NSObject.Type).init() as? InterleavingDataTask
        task?.stubResponse = response
        task?.stubError = error
        return task
    }

    func runOnFirstOutcomeRead(_ work: @escaping () -> Void) {
        armedWork = work
    }

    override var response: URLResponse? {
        runArmedWork()
        return stubResponse
    }

    override var error: Error? {
        runArmedWork()
        return stubError
    }

    private func runArmedWork() {
        let work = armedWork
        armedWork = nil
        work?()
    }
}

final class NetworkResponseBodyCompletionRaceTests: XCTestCase {

    private static let url = URL(string: "https://api.example.com/posts/1")!
    private static let body = Data(#"{"id":1,"title":"payload"}"#.utf8)

    private var instrumentation: URLSessionInstrumentation!
    private var session: URLSession!
    private let lock = NSLock()
    private var responseBodies: [Data?] = []
    private var errorBodies: [Data?] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        responseBodies = []
        errorBodies = []
        session = URLSession(configuration: .ephemeral)
        let configuration = URLSessionInstrumentationConfiguration(
            shouldInstrument: { _ in true },
            shouldInjectTracingHeaders: { _ in false },
            shouldCollectResponsePayload: { _ in true },
            receivedResponse: { [weak self] _, dataOrFile, _, _ in
                self?.record(NetworkCaptureRule.responseData(from: dataOrFile), in: \.responseBodies)
            },
            receivedError: { [weak self] _, dataOrFile, _, _ in
                self?.record(NetworkCaptureRule.responseData(from: dataOrFile), in: \.errorBodies)
            },
            // A provider of its own, so ended spans never reach an exporter another test installed.
            tracer: TracerProviderSdk().get(instrumentationName: "NetworkResponseBodyCompletionRaceTests")
        )
        instrumentation = URLSessionInstrumentation(configuration: configuration)
    }

    override func tearDownWithError() throws {
        instrumentation = nil
        session.invalidateAndCancel()
        session = nil
        try super.tearDownWithError()
    }

    // MARK: - Concurrent completion paths

    /// The pairing CFNetwork produces: it runs the setState: fallback on its own queue at the moment it
    /// dispatches didFinishCollectingMetrics to the delegate queue.
    func test_fallbackCompletingInsideMetricsCallback_spanEndsWithBody() throws {
        let (task, _) = try makeTaskWithBufferedBody()
        let metrics = try XCTUnwrap((URLSessionTaskMetrics.self as NSObject.Type).init() as? URLSessionTaskMetrics)
        task.runOnFirstOutcomeRead { [instrumentation] in
            instrumentation?.urlSessionTaskDidChangeState(task, newState: .completed)
        }

        instrumentation.urlSession(session, task: task, didFinishCollecting: metrics)

        assertSpanEndedOnceWithBody()
    }

    /// The setState: fallback completes the task while the delegate's didCompleteWithError is mid-way.
    func test_fallbackCompletingInsideDelegateCompletion_spanEndsWithBody() throws {
        let (task, _) = try makeTaskWithBufferedBody()
        task.runOnFirstOutcomeRead { [instrumentation] in
            instrumentation?.urlSessionTaskDidChangeState(task, newState: .completed)
        }

        instrumentation.urlSession(session, task: task, didCompleteWithError: nil)

        assertSpanEndedOnceWithBody()
    }

    /// The delegate's didCompleteWithError completes the task while the setState: fallback is mid-way.
    func test_delegateCompletingInsideFallback_spanEndsWithBody() throws {
        let (task, _) = try makeTaskWithBufferedBody()
        let session: URLSession = self.session
        task.runOnFirstOutcomeRead { [instrumentation] in
            instrumentation?.urlSession(session, task: task, didCompleteWithError: nil)
        }

        instrumentation.urlSessionTaskDidChangeState(task, newState: .completed)

        assertSpanEndedOnceWithBody()
    }

    // MARK: - The body follows the span claim

    func test_failedRequest_errorSpanCarriesBody() throws {
        let failure = URLError(.networkConnectionLost)
        let (task, _) = try makeTaskWithBufferedBody(statusCode: 500, error: failure)

        instrumentation.urlSession(session, task: task, didCompleteWithError: failure)

        lock.lock()
        let bodies = errorBodies
        lock.unlock()
        XCTAssertEqual(bodies.count, 1, "the failed task's span must be ended exactly once")
        XCTAssertEqual(bodies.first ?? nil, Self.body, "the error path must carry the buffered response body")
    }

    func test_nonHTTPResponse_claimingTheSpanFreesTheBody() throws {
        let response = URLResponse(url: Self.url, mimeType: "application/json",
                                   expectedContentLength: Self.body.count, textEncodingName: nil)
        let (task, taskId) = try makeTaskWithBufferedBody(response: response)

        instrumentation.urlSession(session, task: task, didCompleteWithError: nil)

        XCTAssertNil(instrumentation.takeResponseBody(forTaskId: taskId),
                     "the body buffered for a non-HTTP response must not outlive its task")
    }

    func test_bodyBufferedAfterAnotherPathCompleted_isFreedByDidComplete() throws {
        let (task, taskId) = try makeTaskWithBufferedBody()
        instrumentation.urlSessionTaskDidChangeState(task, newState: .completed)
        instrumentation.urlSession(session, dataTask: task, didReceive: Data("late".utf8))

        instrumentation.urlSession(session, task: task, didCompleteWithError: nil)

        assertSpanEndedOnceWithBody()
        XCTAssertNil(instrumentation.takeResponseBody(forTaskId: taskId),
                     "a body buffered after another path ended the span must not outlive its task")
    }

    // MARK: - Helpers

    /// A running task with its response body buffered: the state every completion path finds once
    /// CFNetwork has delivered the body to the session delegate.
    private func makeTaskWithBufferedBody(statusCode: Int = 200,
                                          error: Error? = nil) throws -> (InterleavingDataTask, String) {
        let response = try XCTUnwrap(HTTPURLResponse(url: Self.url,
                                                     statusCode: statusCode,
                                                     httpVersion: nil,
                                                     headerFields: ["Content-Type": "application/json"]))
        return try makeTaskWithBufferedBody(response: response, error: error)
    }

    private func makeTaskWithBufferedBody(response: URLResponse,
                                          error: Error? = nil) throws -> (InterleavingDataTask, String) {
        let request = URLRequest(url: Self.url)
        let task = try XCTUnwrap(InterleavingDataTask.make(response: response, error: error))
        let taskId = UUID().uuidString
        instrumentation.setIdKey(value: taskId, for: task)
        instrumentation.storeRequest(request, forTaskId: taskId)
        URLSessionLogger.processAndLogRequest(request,
                                              sessionTaskId: taskId,
                                              instrumentation: instrumentation,
                                              shouldInjectHeaders: false)
        instrumentation.urlSession(session, dataTask: task, didReceive: Self.body)
        return (task, taskId)
    }

    private func record(_ body: Data?, in bodies: ReferenceWritableKeyPath<NetworkResponseBodyCompletionRaceTests, [Data?]>) {
        lock.lock()
        self[keyPath: bodies].append(body)
        lock.unlock()
    }

    private func assertSpanEndedOnceWithBody(file: StaticString = #filePath, line: UInt = #line) {
        lock.lock()
        let bodies = responseBodies
        lock.unlock()
        XCTAssertEqual(bodies.count, 1, "the task's span must be ended exactly once", file: file, line: line)
        XCTAssertEqual(bodies.first ?? nil, Self.body,
                       "the path that ended the span must carry the buffered response body",
                       file: file, line: line)
    }
}
