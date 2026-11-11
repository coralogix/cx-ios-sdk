//
//  SpanUploaderClassificationTests.swift
//
//  How a finished upload maps onto crash delivery: delivered, rejected for good, worth a
//  retry (counted or not), or never attempted; `Retry-After` in both of its forms; and the
//  request timeouts for a live batch versus a stored crash.
//

import XCTest
import CoralogixInternal

@testable import Coralogix

final class SpanUploaderClassificationTests: XCTestCase {

    private let url = URL(string: "https://ingress.example.com/browser/v1beta/logs")!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func classify(_ status: Int, headers: [String: String] = [:], isOnline: Bool = true) -> SpanUploadResult {
        SpanUploader.classify(response: response(status, headers: headers), error: nil, isOnline: isOnline, now: now)
    }

    // MARK: - Status codes

    func test_2xx_isDelivered_andNotCounted() {
        for status in [200, 202, 204, 299] {
            let result = classify(status)
            XCTAssertEqual(result.disposition, .delivered, "HTTP \(status)")
            XCTAssertEqual(result.httpStatus, status)
            XCTAssertFalse(result.countsAsFailedUpload, "HTTP \(status)")
            XCTAssertEqual(result.resultCode, .success)
        }
    }

    func test_408_429_and5xx_areRetryable_andCounted() {
        for status in [408, 429, 500, 502, 503, 599] {
            let result = classify(status)
            XCTAssertEqual(result.disposition, .retryable, "HTTP \(status)")
            XCTAssertTrue(result.countsAsFailedUpload, "HTTP \(status)")
            XCTAssertEqual(result.resultCode, .failure)
        }
    }

    func test_other4xx_isPermanentReject_andNotCounted() {
        for status in [400, 401, 403, 404, 413, 422] {
            let result = classify(status)
            XCTAssertEqual(result.disposition, .permanentReject, "HTTP \(status)")
            XCTAssertFalse(result.countsAsFailedUpload, "HTTP \(status)")
        }
    }

    func test_statusIsClassifiedTheSameWhileOffline() {
        // A server answer means the network worked; reachability only matters for transport errors.
        XCTAssertEqual(classify(503, isOnline: false).countsAsFailedUpload, true)
        XCTAssertEqual(classify(400, isOnline: false).disposition, .permanentReject)
    }

    // MARK: - Transport errors

    func test_urlError_isRetryable_andCountedOnlyWhileOnline() {
        for code in [URLError.Code.timedOut, .cannotFindHost, .notConnectedToInternet, .networkConnectionLost] {
            let error = URLError(code)
            let online = SpanUploader.classify(response: nil, error: error, isOnline: true, now: now)
            let offline = SpanUploader.classify(response: nil, error: error, isOnline: false, now: now)
            XCTAssertEqual(online.disposition, .retryable, "\(code)")
            XCTAssertTrue(online.countsAsFailedUpload, "\(code) online")
            XCTAssertEqual(offline.disposition, .retryable, "\(code)")
            XCTAssertFalse(offline.countsAsFailedUpload, "\(code) offline")
        }
    }

    func test_ourOwnCancellation_isNotAttempted() {
        let result = SpanUploader.classify(response: nil, error: URLError(.cancelled), isOnline: true, now: now)
        XCTAssertEqual(result.disposition, .notAttempted)
        XCTAssertFalse(result.countsAsFailedUpload)
    }

    func test_nonURLError_isCountedEvenWhileOffline() {
        struct Unexpected: Error {}
        let result = SpanUploader.classify(response: nil, error: Unexpected(), isOnline: false, now: now)
        XCTAssertEqual(result.disposition, .retryable)
        XCTAssertTrue(result.countsAsFailedUpload)
    }

    // MARK: - Retry-After

    func test_retryAfter_deltaSeconds() {
        XCTAssertEqual(classify(503, headers: ["Retry-After": "120"]).retryAfter, 120)
        XCTAssertEqual(classify(429, headers: ["retry-after": " 30 "]).retryAfter, 30)
        XCTAssertEqual(classify(503, headers: ["Retry-After": "0"]).retryAfter, 0)
    }

    func test_retryAfter_httpDate_isMeasuredAgainstTheResponseDate() {
        // The device clock (`now`) is far off; the server's own Date header is the reference.
        let headers = ["Date": "Wed, 21 Oct 2026 07:28:00 GMT",
                       "Retry-After": "Wed, 21 Oct 2026 07:30:00 GMT"]
        XCTAssertEqual(classify(503, headers: headers).retryAfter, 120)
    }

    func test_retryAfter_httpDate_fallsBackToTheDeviceClock() {
        let reference = SpanUploader.parseHTTPDate("Wed, 21 Oct 2026 07:28:00 GMT")!
        let value = SpanUploader.parseRetryAfter("Wed, 21 Oct 2026 07:29:30 GMT", responseDate: nil, now: reference)
        XCTAssertEqual(value, 90)
    }

    func test_retryAfter_negativeOrGarbage_isNone() {
        XCTAssertNil(classify(503, headers: ["Retry-After": "-5"]).retryAfter)
        XCTAssertNil(classify(503, headers: ["Retry-After": "soon"]).retryAfter)
        XCTAssertNil(classify(503, headers: ["Retry-After": ""]).retryAfter)
        XCTAssertNil(classify(503).retryAfter)
        let past = ["Date": "Wed, 21 Oct 2026 07:28:00 GMT",
                    "Retry-After": "Wed, 21 Oct 2026 07:00:00 GMT"]
        XCTAssertNil(classify(503, headers: past).retryAfter)
    }

    func test_retryAfter_isCappedAtOneHour() {
        XCTAssertEqual(classify(503, headers: ["Retry-After": "86400"]).retryAfter, 3600)
        XCTAssertEqual(classify(503, headers: ["Retry-After": "3600"]).retryAfter, 3600)
        XCTAssertEqual(classify(503, headers: ["Retry-After": "3599"]).retryAfter, 3599)
    }

    // MARK: - Timeouts

    func test_liveBatch_uses10sRequestTimeout() {
        let request = SpanUploader.makeRequest(url: url, kind: .live)
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func test_storedCrash_uses45sRequestAnd120sTotal() {
        let request = SpanUploader.makeRequest(url: url, kind: .storedCrash)
        XCTAssertEqual(request.timeoutInterval, 45)

        let uploader = SpanUploader(options: CoralogixExporterOptions(coralogixDomain: .EU2,
                                                                      userContext: nil,
                                                                      environment: "test",
                                                                      application: "app",
                                                                      version: "1.0",
                                                                      publicKey: "key"))
        let configuration = uploader.storedCrashSession.configuration
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 45)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 120)
    }

    // MARK: - Not attempted

    func test_uploadBeforeInit_isNotAttempted() {
        let wasInitialized = CoralogixRum.isInitialized
        CoralogixRum.isInitialized = false
        defer { CoralogixRum.isInitialized = wasInitialized }

        let uploader = SpanUploader(options: CoralogixExporterOptions(coralogixDomain: .EU2,
                                                                      userContext: nil,
                                                                      environment: "test",
                                                                      application: "app",
                                                                      version: "1.0",
                                                                      publicKey: "key"))
        let result = uploader.upload([["k": "v"]], endPoint: url.absoluteString, kind: .storedCrash)
        XCTAssertEqual(result.disposition, .notAttempted)
        XCTAssertFalse(result.countsAsFailedUpload)
        XCTAssertEqual(result.resultCode, .failure)
    }
}
