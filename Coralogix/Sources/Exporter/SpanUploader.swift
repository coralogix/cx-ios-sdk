//
//  SpanUploader.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 30/07/2025.
//

import Foundation
import CoralogixInternal

/// What became of one upload, in the terms crash delivery needs: whether the copy on disk can
/// be deleted, retried, or left untouched for a later launch.
enum SpanUploadDisposition: Equatable {
    /// 2xx: the backend has the events.
    case delivered
    /// A 4xx other than 408 and 429, or a payload that could not be encoded: sending it again
    /// cannot succeed.
    case permanentReject
    /// 408, 429, 5xx, or a transport error: worth sending again.
    case retryable
    /// No request went out: the SDK was not initialized, the URL was invalid, or we cancelled it.
    case notAttempted
}

/// Which request settings an upload uses. A stored crash gets longer timeouts than a live
/// batch, because it is sent once per launch and a slow network should not lose it.
enum SpanUploadKind: Equatable {
    case live
    case storedCrash
}

struct SpanUploadResult: Equatable {
    let disposition: SpanUploadDisposition
    let httpStatus: Int?
    /// Seconds the backend asked us to wait, from `Retry-After`, capped at one hour.
    let retryAfter: TimeInterval?
    /// Whether this attempt counts toward a stored crash's failed-upload limit. A transport
    /// error while the device is offline is retried without being counted.
    let countsAsFailedUpload: Bool

    var resultCode: SpanExporterResultCode {
        disposition == .delivered ? .success : .failure
    }

    static let delivered = SpanUploadResult(disposition: .delivered, httpStatus: nil, retryAfter: nil, countsAsFailedUpload: false)
    static let notAttempted = SpanUploadResult(disposition: .notAttempted, httpStatus: nil, retryAfter: nil, countsAsFailedUpload: false)
    static let permanentReject = SpanUploadResult(disposition: .permanentReject, httpStatus: nil, retryAfter: nil, countsAsFailedUpload: false)
}

/// What became of one stored crash this process tried to send.
enum CrashUploadOutcome: Equatable {
    case delivered
    /// Refused for good by the backend (a 4xx other than 408/429, or an unencodable payload).
    case rejected
    /// Dropped before sending by sampling, `ignoreErrors` or the native `beforeSend`.
    case policyDropped
    /// Worth sending again; `counted` says whether it uses up one of the crash's attempts.
    case failed(counted: Bool)
    case notAttempted

    init(_ result: SpanUploadResult) {
        switch result.disposition {
        case .delivered: self = .delivered
        case .permanentReject: self = .rejected
        case .retryable: self = .failed(counted: result.countsAsFailedUpload)
        case .notAttempted: self = .notAttempted
        }
    }

    /// Whether the stored copy can be deleted: nothing more will come of sending it again.
    var isFinished: Bool {
        switch self {
        case .delivered, .rejected, .policyDropped: return true
        case .failed, .notAttempted: return false
        }
    }
}

protocol SpanUploading {
    @discardableResult
    func upload(_ spans: [[String: Any]], endPoint: String, kind: SpanUploadKind) -> SpanUploadResult
}

extension SpanUploading {
    @discardableResult
    func upload(_ spans: [[String: Any]], endPoint: String) -> SpanUploadResult {
        upload(spans, endPoint: endPoint, kind: .live)
    }
}

final class SpanUploader: SpanUploading {
    static let liveRequestTimeout: TimeInterval = 10
    static let storedCrashRequestTimeout: TimeInterval = 45
    static let storedCrashResourceTimeout: TimeInterval = 120
    static let maxRetryAfter: TimeInterval = 60 * 60

    private let options: CoralogixExporterOptions
    private let isOnline: () -> Bool

    internal lazy var storedCrashSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Self.storedCrashRequestTimeout
        configuration.timeoutIntervalForResource = Self.storedCrashResourceTimeout
        return URLSession(configuration: configuration)
    }()
    private let sessionLock = NSLock()

    init(options: CoralogixExporterOptions, isOnline: @escaping () -> Bool = { true }) {
        self.options = options
        self.isOnline = isOnline
    }

    @discardableResult
    func upload(_ spans: [[String: Any]], endPoint: String, kind: SpanUploadKind) -> SpanUploadResult {
        guard CoralogixRum.isInitialized,
              let urlString = self.resolvedUrlString(endPoint: endPoint),
              let url = URL(string: urlString) else {
            return .notAttempted
        }

        var request = Self.makeRequest(url: url, kind: kind)
        request.addValue("Bearer \(self.options.publicKey)", forHTTPHeaderField: "Authorization")

        let jsonObject: [String: Any] = [
            Keys.logs.rawValue: spans,
            Keys.skipEnrichmentWithIp.rawValue: !options.collectIPData
        ]

        let requestJsonData: Data
        do {
            requestJsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
            request.httpBody = requestJsonData
        } catch {
            Log.e(error)
            return .permanentReject
        }

        var result = SpanUploadResult.notAttempted
        let semaphore = DispatchSemaphore(value: 0)
        let task = session(for: kind).dataTask(with: request) { [weak self] data, response, error in
            defer { semaphore.signal() }

            result = Self.classify(response: response as? HTTPURLResponse,
                                   error: error,
                                   isOnline: self?.isOnline() ?? true,
                                   now: Date())
            self?.logOutcome(result, error: error, responseBody: data, requestJSON: requestJsonData)
        }

        task.resume()
        semaphore.wait()
        return result
    }

    private func logOutcome(_ result: SpanUploadResult, error: Error?, responseBody: Data?, requestJSON: Data) {
        switch result.disposition {
        case .delivered:
            logJSON(from: requestJSON, prettyPrint: true)
        case .permanentReject, .retryable:
            if let error = error {
                Log.e("[SpanUploader] Network error: \(error.localizedDescription)")
                return
            }
            let rawBody = responseBody.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
            let body = rawBody.count > 512 ? String(rawBody.prefix(512)) + "…" : rawBody
            Log.e("[SpanUploader] Backend rejected upload with HTTP \(result.httpStatus ?? 0): \(body)")
        case .notAttempted:
            break
        }
    }

    private func session(for kind: SpanUploadKind) -> URLSession {
        switch kind {
        case .live:
            return URLSession.shared
        case .storedCrash:
            sessionLock.lock()
            defer { sessionLock.unlock() }
            return storedCrashSession
        }
    }

    static func makeRequest(url: URL, kind: SpanUploadKind) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = kind == .live ? liveRequestTimeout : storedCrashRequestTimeout
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Maps a finished request onto what crash delivery should do next. Mirrors the Android
    /// SDK so a crash is retried, dropped or kept under the same conditions on both platforms.
    static func classify(response: HTTPURLResponse?,
                         error: Error?,
                         isOnline: Bool,
                         now: Date) -> SpanUploadResult {
        if (error as? URLError)?.code == .cancelled {
            return .notAttempted
        }
        guard error == nil, let response = response else {
            // A transport error says nothing about the server while offline, so it is not
            // counted then; anything else that failed the call is.
            let counted = error.map { $0 is URLError ? isOnline : true } ?? isOnline
            return SpanUploadResult(disposition: .retryable,
                                    httpStatus: nil,
                                    retryAfter: nil,
                                    countsAsFailedUpload: counted)
        }

        let status = response.statusCode
        let retryAfter = parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After"),
                                         responseDate: response.value(forHTTPHeaderField: "Date"),
                                         now: now)
        let disposition: SpanUploadDisposition
        switch status {
        case 200..<300:
            disposition = .delivered
        case 408, 429:
            disposition = .retryable
        case 400..<500:
            disposition = .permanentReject
        default:
            disposition = .retryable
        }
        return SpanUploadResult(disposition: disposition,
                                httpStatus: status,
                                retryAfter: retryAfter,
                                countsAsFailedUpload: disposition == .retryable)
    }

    /// `Retry-After` is either a number of seconds or an HTTP date. A date is measured against
    /// the response's own `Date` header, so a device clock that is off does not skew it.
    static func parseRetryAfter(_ value: String?, responseDate: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }

        let seconds: TimeInterval
        if let delta = Int(value) {
            seconds = TimeInterval(delta)
        } else if let date = parseHTTPDate(value) {
            let reference = responseDate.flatMap(parseHTTPDate) ?? now
            seconds = date.timeIntervalSince(reference)
        } else {
            return nil
        }

        guard seconds >= 0 else { return nil }
        return min(seconds, maxRetryAfter)
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
    private static let httpDateLock = NSLock()

    static func parseHTTPDate(_ value: String) -> Date? {
        httpDateLock.lock()
        defer { httpDateLock.unlock() }
        return httpDateFormatter.date(from: value)
    }

    internal func resolvedUrlString(endPoint: String) -> String? {
        if let proxyUrl = self.options.proxyUrl,
            var urlComponents = URLComponents(string: proxyUrl) {
            urlComponents.queryItems = [
                URLQueryItem(name: Keys.cxforward.rawValue, value: endPoint)
            ]
            return urlComponents.url?.absoluteString
        } else {
            return endPoint
        }
    }

    internal func logJSON(from jsonData: Data, prettyPrint: Bool) {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []) else {
            return
        }

        let options: JSONSerialization.WritingOptions = prettyPrint ? .prettyPrinted : []

        if let formattedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: options),
           let jsonString = String(data: formattedData, encoding: .utf8) {
            Log.d("📤 Sending to Coralogix:\n\(jsonString)")
        }
    }
}
