#!/usr/bin/env swift
// Native-Swift replacement for mock_upload_server.dart.
//
// Listens on a POSIX TCP socket, intercepts session-replay multipart
// uploads from the DemoApp (routed there by CX_MOCK_PORT), gzip-
// decompresses each `chunk` field, and saves the resulting JPEG into a
// temp directory.
//
// Startup protocol (consumed by run_leak_harness.sh):
//   CX_MOCK_PORT=<port>
//   CX_MOCK_DIR=<path>
//   [mock-upload] ready
//
// Routes:
//   POST /scenario?name=<tag>   → set scenario prefix for subsequent frames
//   POST *                      → multipart/form-data upload handler

import Foundation
import Darwin

// MARK: - Shared state

let stateQueue = DispatchQueue(label: "cx.mock.state")
var currentScenario = "unknown"
var sequenceNumber = 0
let framesDir: URL = {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    let d = tmp.appendingPathComponent("cx_leak_harness_\(Int.random(in: 10000...99999))")
    try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}()

// MARK: - Socket helpers

func createServerSocket(port: UInt16) -> (fd: Int32, port: UInt16) {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { fatalError("socket() failed: \(errno)") }

    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_in()
    memset(&addr, 0, MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(port).bigEndian
    addr.sin_addr.s_addr = 0 // INADDR_ANY
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

    let bindRes = withUnsafeMutablePointer(to: &addr) { p in
        p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindRes == 0 else { fatalError("bind() failed: \(errno)") }
    guard Darwin.listen(fd, 32) == 0 else { fatalError("listen() failed: \(errno)") }

    var bound = sockaddr_in()
    var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
    withUnsafeMutablePointer(to: &bound) { p in
        p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &boundLen) }
    }
    return (fd, in_port_t(bigEndian: bound.sin_port))
}

func recvAll(fd: Int32, count: Int) -> Data? {
    var buf = Data(count: count)
    var n = 0
    while n < count {
        let r = buf.withUnsafeMutableBytes { recv(fd, $0.baseAddress! + n, count - n, 0) }
        if r <= 0 { return n > 0 ? buf.prefix(n) : nil }
        n += r
    }
    return buf
}

// MARK: - HTTP parsing

struct HTTPRequest {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data
}

func readRequest(fd: Int32) -> HTTPRequest? {
    var headerBytes = Data()
    var byte = [UInt8](repeating: 0, count: 1)
    while true {
        let n = recv(fd, &byte, 1, 0)
        if n <= 0 { return nil }
        headerBytes.append(byte[0])
        if headerBytes.suffix(4) == Data([0x0d, 0x0a, 0x0d, 0x0a]) { break }
        if headerBytes.count > 65536 { return nil }
    }

    guard let headerStr = String(data: headerBytes, encoding: .utf8) else { return nil }
    let lines = headerStr.components(separatedBy: "\r\n").filter { !$0.isEmpty }
    guard let requestLine = lines.first else { return nil }

    let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
    guard parts.count >= 2 else { return nil }

    let method  = parts[0]
    let rawPath = parts[1]
    var path    = rawPath
    var query: [String: String] = [:]
    if let qi = rawPath.firstIndex(of: "?") {
        path = String(rawPath[..<qi])
        for kv in String(rawPath[rawPath.index(after: qi)...]).components(separatedBy: "&") {
            let p = kv.components(separatedBy: "=")
            if p.count == 2 {
                query[p[0].removingPercentEncoding ?? p[0]] = p[1].removingPercentEncoding ?? p[1]
            }
        }
    }

    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
        if let c = line.firstIndex(of: ":") {
            let k = String(line[..<c]).trimmingCharacters(in: .whitespaces).lowercased()
            let v = String(line[line.index(after: c)...]).trimmingCharacters(in: .whitespaces)
            headers[k] = v
        }
    }

    var body = Data()
    if let lenStr = headers["content-length"], let len = Int(lenStr), len > 0 {
        body = recvAll(fd: fd, count: len) ?? Data()
    }

    return HTTPRequest(method: method, path: path, query: query, headers: headers, body: body)
}

func sendResponse(fd: Int32, status: Int = 200, body: String = "") {
    let s = "HTTP/1.1 \(status) OK\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    var bytes = Array(s.utf8)
    send(fd, &bytes, bytes.count, 0)
}

// MARK: - Multipart parsing

func extractBoundary(from ct: String) -> String? {
    for seg in ct.components(separatedBy: ";") {
        let t = seg.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("boundary=") {
            var b = String(t.dropFirst("boundary=".count))
            if b.hasPrefix("\"") && b.hasSuffix("\"") { b = String(b.dropFirst().dropLast()) }
            return b
        }
    }
    return nil
}

func parseMultipart(body: Data, boundary: String) -> [String: Data] {
    var result: [String: Data] = [:]
    let delim      = Data(("--" + boundary).utf8)
    let crlfDelim  = Data(("\r\n--" + boundary).utf8)
    let crlf2      = Data([0x0d, 0x0a, 0x0d, 0x0a])
    let crlf       = Data([0x0d, 0x0a])

    // Locate first --boundary
    guard let first = body.range(of: delim) else { return result }
    var cursor = first.upperBound
    guard body[cursor...].prefix(2) == crlf else { return result }
    cursor += 2

    while cursor < body.count {
        guard let sep = body.range(of: crlf2, in: cursor..<body.count) else { break }
        let headerData = body[cursor..<sep.lowerBound]
        let bodyStart  = sep.upperBound

        var fieldName: String? = nil
        if let hs = String(data: headerData, encoding: .utf8) {
            for line in hs.components(separatedBy: "\r\n") {
                if line.lowercased().hasPrefix("content-disposition:"),
                   let nr = line.range(of: "name=\"") {
                    let after = line[nr.upperBound...]
                    if let eq = after.firstIndex(of: "\"") { fieldName = String(after[..<eq]) }
                }
            }
        }

        guard let nextDelim = body.range(of: crlfDelim, in: bodyStart..<body.count) else { break }
        if let name = fieldName { result[name] = Data(body[bodyStart..<nextDelim.lowerBound]) }

        cursor = nextDelim.upperBound
        if body[cursor...].prefix(2) == Data("--".utf8) { break }
        if body[cursor...].prefix(2) == crlf { cursor += 2 } else { break }
    }
    return result
}

// MARK: - Gzip decompression

func maybeDecompress(_ data: Data) -> Data {
    guard data.count >= 2, data[0] == 0x1f, data[1] == 0x8b else { return data }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
    p.arguments = ["-c"]
    let inPipe = Pipe(); let outPipe = Pipe()
    p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = Pipe()
    guard (try? p.run()) != nil else { return data }
    inPipe.fileHandleForWriting.write(data)
    inPipe.fileHandleForWriting.closeFile()
    let out = outPipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return out.isEmpty ? data : out
}

// MARK: - Request routing

func handle(req: HTTPRequest) {
    if req.method == "POST" && req.path == "/scenario" {
        let name = req.query["name"] ?? "unknown"
        stateQueue.sync { currentScenario = name }
        print("[mock-upload] ── scenario → \(name) ──")
        fflush(stdout)
        return
    }
    guard req.method == "POST" else { return }

    let ct = req.headers["content-type"] ?? ""
    guard ct.contains("multipart/form-data"), let boundary = extractBoundary(from: ct) else {
        if !ct.isEmpty { fputs("[mock-upload] WARNING: unexpected content-type: \(ct)\n", stderr) }
        return
    }

    let parts = parseMultipart(body: req.body, boundary: boundary)
    guard let chunk = parts["chunk"] else {
        fputs("[mock-upload] WARNING: no 'chunk' field in multipart upload\n", stderr)
        return
    }

    let decoded = maybeDecompress(chunk)
    let (seq, scenario) = stateQueue.sync { () -> (Int, String) in
        let s = sequenceNumber; sequenceNumber += 1; return (s, currentScenario)
    }

    let frameName = String(format: "\(scenario)_frame_%06d.jpg", seq)
    try? decoded.write(to: framesDir.appendingPathComponent(frameName))
    if let meta = parts["metadata"] {
        try? meta.write(to: framesDir.appendingPathComponent(String(format: "\(scenario)_meta_%06d.json", seq)))
    }

    print("[mock-upload] [\(scenario)] #\(seq)  \(chunk.count)B→\(decoded.count)B  \(frameName)")
    fflush(stdout)
}

// MARK: - Accept loop

func acceptLoop(serverFd: Int32) {
    var clientAddr = sockaddr_in()
    var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
    while true {
        let cfd = withUnsafeMutablePointer(to: &clientAddr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.accept(serverFd, $0, &addrLen) }
        }
        guard cfd >= 0 else { continue }
        DispatchQueue.global().async {
            defer { close(cfd) }
            if let req = readRequest(fd: cfd) {
                handle(req: req)
                sendResponse(fd: cfd)
            }
        }
    }
}

// MARK: - Entry point

let requestedPort = UInt16(CommandLine.arguments.dropFirst().first ?? "0") ?? 0
let (serverFd, boundPort) = createServerSocket(port: requestedPort)

print("CX_MOCK_PORT=\(boundPort)")
print("CX_MOCK_DIR=\(framesDir.path)")
print("[mock-upload] ready")
fflush(stdout)

signal(SIGTERM) { _ in exit(0) }
signal(SIGINT)  { _ in exit(0) }

DispatchQueue.global().async { acceptLoop(serverFd: serverFd) }
RunLoop.main.run()
