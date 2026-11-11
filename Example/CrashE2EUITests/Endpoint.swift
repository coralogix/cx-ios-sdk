//
//  Endpoint.swift
//  CrashE2EUITests
//
//  The ingress the e2e host app sends to: an HTTP/1.1 server on 127.0.0.1 inside the UI test runner
//  (the simulator shares the host's network), like Android's MockWebServer endpoint. It answers each
//  request that carries a crash as the test scripts it — a status, a Retry-After, or no answer at
//  all — and every other request 200, and records what arrived.
//

import Foundation
import Network

final class Endpoint {
    struct Answer {
        var status = 200
        /// Sent as the `Retry-After` header: delta-seconds or an HTTP-date.
        var retryAfter: String?
        /// No answer at all: the connection is left open until the endpoint stops.
        var hang = false
        /// Waits this long before answering.
        var delay: TimeInterval = 0

        static let ok = Answer()
        static func status(_ status: Int, retryAfter: String? = nil) -> Answer {
            Answer(status: status, retryAfter: retryAfter)
        }
        static let noAnswer = Answer(hang: true)
    }

    struct Request {
        let arrival: Date
        /// The `cx_rum` of each event the request carried.
        let events: [[String: Any]]
        let answer: Answer

        var crashes: [[String: Any]] {
            events.filter { ($0["error_context"] as? [String: Any])?["is_crash"] as? Bool == true }
        }
        var isCrash: Bool { !crashes.isEmpty }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "crash-e2e.endpoint")
    private let lock = NSLock()
    private var _requests: [Request] = []
    private var script: [Answer] = []
    private var crashDefault = Answer.ok
    private var liveAnswer = Answer.ok
    private var openConnections: [NWConnection] = []
    private(set) var port: UInt16 = 0

    var url: String { "http://127.0.0.1:\(port)" }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 10) == .success, let port = listener.port?.rawValue else {
            throw NSError(domain: "Endpoint", code: 1, userInfo: [NSLocalizedDescriptionKey: "listener did not start"])
        }
        self.port = port
    }

    func stop() {
        listener.cancel()
        lock.lock()
        let open = openConnections
        openConnections = []
        lock.unlock()
        open.forEach { $0.cancel() }
    }

    /// The answers to the next requests that carry a crash, in order; then `then` for every later one.
    func answerCrashes(_ answers: [Answer], then fallback: Answer = .ok) {
        lock.lock()
        script = answers
        crashDefault = fallback
        lock.unlock()
    }

    /// The answer to every request that carries no crash.
    func answerLive(_ answer: Answer) {
        lock.lock()
        liveAnswer = answer
        lock.unlock()
    }

    var requests: [Request] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    var crashRequests: [Request] { requests.filter(\.isCrash) }

    /// Every crash event received, in arrival order.
    var crashes: [[String: Any]] { crashRequests.flatMap(\.crashes) }

    /// Every event received, in arrival order.
    var events: [[String: Any]] { requests.flatMap(\.events) }

    // MARK: - HTTP

    private func accept(_ connection: NWConnection) {
        lock.lock()
        openConnections.append(connection)
        lock.unlock()
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.handle(body: request, on: connection)
            } else if error == nil, !isComplete {
                self.receive(on: connection, buffer: buffer)
            } else {
                connection.cancel()
            }
        }
    }

    /// The body of a complete request in `buffer`, or nil while more is to come.
    private static func parse(_ buffer: Data) -> Data? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let header = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self).lowercased()
        let length = header.components(separatedBy: "\r\n")
            .first { $0.hasPrefix("content-length:") }
            .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
        let body = buffer[headerEnd.upperBound...]
        return body.count >= length ? Data(body.prefix(length)) : nil
    }

    private func handle(body: Data, on connection: NWConnection) {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let logs = json?["logs"] as? [[String: Any]] ?? []
        let events = logs.compactMap { ($0["text"] as? [String: Any])?["cx_rum"] as? [String: Any] }
        let carriesCrash = events.contains { ($0["error_context"] as? [String: Any])?["is_crash"] as? Bool == true }

        lock.lock()
        let answer: Answer
        if carriesCrash {
            answer = script.isEmpty ? crashDefault : script.removeFirst()
        } else {
            answer = liveAnswer
        }
        _requests.append(Request(arrival: Date(), events: events, answer: answer))
        lock.unlock()

        guard !answer.hang else { return }
        queue.asyncAfter(deadline: .now() + answer.delay) {
            var head = "HTTP/1.1 \(answer.status) \(answer.status < 300 ? "OK" : "Error")\r\nContent-Length: 2\r\nConnection: close\r\n"
            if let retryAfter = answer.retryAfter { head += "Retry-After: \(retryAfter)\r\n" }
            head += "Date: \(Self.httpDate(Date()))\r\n\r\n{}"
            connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }
}
