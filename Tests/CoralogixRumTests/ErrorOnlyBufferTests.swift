//
//  ErrorOnlyBufferTests.swift
//
//  The on-disk buffer of sessions held until an error, and the paced drain that sends it once
//  they have one. The drain runs on a manual clock, so every gap and retry slot is stepped.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class ErrorOnlyBufferTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ErrorOnlyBuffer-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: - Holding and chunking

    func testSmallEvents_fitOneRequestOf500() throws {
        let buffer = makeBuffer()
        (0..<500).forEach { buffer.hold(event($0), sessionId: "s") }
        buffer.trigger("s")

        let chunk = try XCTUnwrap(buffer.nextChunk(of: "s", maxEvents: 500, maxBytes: ErrorOnlyDrain.maxBytesPerRequest))
        XCTAssertEqual(chunk.events.map(index), Array(0..<500), "Oldest first, whole events.")
        buffer.commit(chunk)
        XCTAssertNil(buffer.nextChunk(of: "s", maxEvents: 500, maxBytes: ErrorOnlyDrain.maxBytesPerRequest))
    }

    func testLargeEvents_closeARequestAt1_5MB() throws {
        let buffer = makeBuffer()
        let nearlyOneMB = 1_000 * 1_000
        (0..<3).forEach { buffer.hold(event($0, padding: nearlyOneMB), sessionId: "s") }
        buffer.trigger("s")

        var sizes: [Int] = []
        while let chunk = buffer.nextChunk(of: "s", maxEvents: 500, maxBytes: ErrorOnlyDrain.maxBytesPerRequest) {
            let bytes = try JSONSerialization.data(withJSONObject: chunk.events).count
            XCTAssertLessThanOrEqual(bytes, ErrorOnlyDrain.maxBytesPerRequest)
            sizes.append(chunk.events.count)
            buffer.commit(chunk)
        }
        XCTAssertEqual(sizes, [1, 1, 1], "Three ~1 MB events need three requests.")
    }

    func testEventOver1MB_isDropped_othersKept() throws {
        let buffer = makeBuffer()
        buffer.hold(event(0), sessionId: "s")
        buffer.hold(event(1, padding: ErrorOnlyBuffer.maxEventBytes + 1), sessionId: "s")
        buffer.hold(event(2), sessionId: "s")
        buffer.trigger("s")
        let chunk = try XCTUnwrap(buffer.nextChunk(of: "s", maxEvents: 500, maxBytes: ErrorOnlyDrain.maxBytesPerRequest))
        XCTAssertEqual(chunk.events.map(index), [0, 2])
    }

    func testPastMaxRumEvents_theWholeBufferIsCleared() throws {
        let buffer = makeBuffer(maxRumEvents: 3)
        (0..<4).forEach { buffer.hold(event($0), sessionId: "s") }
        XCTAssertNil(buffer.metadata(of: "s"), "Past the cap before an error, everything held goes, like the browser.")

        buffer.hold(event(10), sessionId: "s")
        buffer.trigger("s")
        let chunk = try XCTUnwrap(buffer.nextChunk(of: "s", maxEvents: 500, maxBytes: ErrorOnlyDrain.maxBytesPerRequest))
        XCTAssertEqual(chunk.events.map(index), [10], "It holds again after the clear.")
    }

    func testByteCap_is4KBPerEvent_capped50MB() {
        XCTAssertEqual(makeBuffer(maxRumEvents: 5_000).maxBytes, 5_000 * 4_096)
        XCTAssertEqual(makeBuffer(maxRumEvents: 20_000).maxBytes, 50 * 1_024 * 1_024)
        let buffer = makeBuffer(maxRumEvents: 2)
        buffer.hold(event(0, padding: 9_000), sessionId: "s")
        XCTAssertNil(buffer.metadata(of: "s"), "An event past the byte cap clears the buffer too.")
    }

    func testDiskFull_truncatesToLastRecord_thenHoldsInMemory_andDrainsBothInOrder() throws {
        let writer = FailingWriter(failAfter: 2)
        let buffer = makeBuffer(writer: writer)
        (0..<4).forEach { buffer.hold(event($0), sessionId: "s") }
        let file = directory.appendingPathComponent("s.jsonl")
        let onDisk = try String(contentsOf: file).split(separator: "\n")
        XCTAssertEqual(onDisk.count, 2, "The partial write is cut back to the last whole event.")
        XCTAssertTrue(try String(contentsOf: file).hasSuffix("\n"))

        buffer.trigger("s")
        var drained: [Int] = []
        while let chunk = buffer.nextChunk(of: "s", maxEvents: 500, maxBytes: ErrorOnlyDrain.maxBytesPerRequest) {
            drained += chunk.events.map(index)
            buffer.commit(chunk)
        }
        XCTAssertEqual(drained, [0, 1, 2, 3], "Disk part first, then memory, in order.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "Files go once everything is sent.")
    }

    func testRotation_discardsAnUntriggeredSession_butNotATriggeredOne() {
        let buffer = makeBuffer()
        buffer.hold(event(0), sessionId: "a")
        buffer.hold(event(0), sessionId: "b")
        buffer.trigger("b")
        buffer.discardUntriggered("a")
        buffer.discardUntriggered("b")
        XCTAssertNil(buffer.metadata(of: "a"))
        XCTAssertEqual(buffer.metadata(of: "b")?.triggered, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("a.jsonl").path))
    }

    // MARK: - Leftovers

    func testLeftovers_triggeredDrain_crashedWait_restDeleted() {
        let earlier = makeBuffer()
        ["triggered", "crashed", "plain"].forEach { earlier.hold(event(0), sessionId: $0) }
        earlier.trigger("triggered")

        let relaunch = makeBuffer()
        let toDrain = relaunch.adoptLeftovers { $0.triggered || ["crashed"].contains($0.sessionId) }
        XCTAssertEqual(toDrain, ["triggered"])
        XCTAssertTrue(relaunch.isTriggered("triggered"), "An adopted buffer that had its error is known as triggered.")
        XCTAssertFalse(relaunch.hold(event(1), sessionId: "triggered"), "Nothing more is held for it.")
        XCTAssertNotNil(relaunch.metadata(of: "crashed"), "Kept for its crash to trigger it.")
        XCTAssertNil(relaunch.metadata(of: "plain"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("plain.jsonl").path),
                       "A session that ended without an error leaves nothing behind.")
    }

    // MARK: - Drain

    func testDrain_sendsOneRequestAtATime_oneSecondApart() throws {
        let buffer = makeBuffer()
        (0..<1_200).forEach { buffer.hold(event($0), sessionId: "s") }
        buffer.trigger("s")
        let clock = ManualDeliveryClock()
        let uploader = ScriptedUploads()
        let drain = makeDrain(buffer, clock: clock, uploader: uploader)

        drain.start(["s"])
        drain.waitUntilSettled()
        XCTAssertEqual(uploader.requests.count, 1, "Only one request before the gap.")
        clock.advance(to: clock.now().addingTimeInterval(ErrorOnlyDrain.gapBetweenRequests))
        drain.waitUntilSettled()
        clock.advance(to: clock.now().addingTimeInterval(ErrorOnlyDrain.gapBetweenRequests))
        drain.waitUntilSettled()
        clock.advance(to: clock.now().addingTimeInterval(ErrorOnlyDrain.gapBetweenRequests))
        drain.waitUntilSettled()

        XCTAssertEqual(uploader.requests.map(\.count), [500, 500, 200])
        XCTAssertEqual(uploader.requests.flatMap { $0 }.map(index), Array(0..<1_200), "Oldest first, nothing twice.")
        XCTAssertEqual(uploader.maxInFlight, 1, "Never two requests in flight.")
        XCTAssertNil(buffer.metadata(of: "s"), "Everything sent: the buffer is gone.")
    }

    func testDrain_429WithRetryAfter_waits_thenResumesWithoutDuplicates() throws {
        let buffer = makeBuffer()
        (0..<600).forEach { buffer.hold(event($0), sessionId: "s") }
        buffer.trigger("s")
        let clock = ManualDeliveryClock()
        let uploader = ScriptedUploads(script: [.delivered,
                                                SpanUploadResult(disposition: .retryable, httpStatus: 429,
                                                                 retryAfter: 60, countsAsFailedUpload: true)])
        let drain = makeDrain(buffer, clock: clock, uploader: uploader)

        drain.start(["s"])
        drain.waitUntilSettled()
        clock.advance(to: clock.now().addingTimeInterval(1))
        drain.waitUntilSettled()
        XCTAssertEqual(uploader.requests.map(\.count), [500, 100], "The second request got the 429.")

        clock.advance(to: clock.now().addingTimeInterval(59))
        drain.waitUntilSettled()
        XCTAssertEqual(uploader.requests.count, 2, "Retry-After holds the next request back.")
        clock.advance(to: clock.now().addingTimeInterval(2))
        drain.waitUntilSettled()

        XCTAssertEqual(uploader.requests.map(\.count), [500, 100, 100])
        XCTAssertEqual(uploader.requests[2].map(index), Array(500..<600), "Resumes where it stopped.")
        XCTAssertEqual(buffer.metadata(of: "s")?.failedUploads, 1, "The 429 counted once.")
        clock.advance(to: clock.now().addingTimeInterval(1))
        drain.waitUntilSettled()
        XCTAssertNil(buffer.metadata(of: "s"), "Delivered in the end: nothing left.")
    }

    func testDrain_permanentReject_deletesThatRequest_andGoesOn() {
        let buffer = makeBuffer()
        (0..<700).forEach { buffer.hold(event($0), sessionId: "s") }
        buffer.trigger("s")
        let clock = ManualDeliveryClock()
        let uploader = ScriptedUploads(script: [SpanUploadResult(disposition: .permanentReject, httpStatus: 413,
                                                                 retryAfter: nil, countsAsFailedUpload: false)])
        let drain = makeDrain(buffer, clock: clock, uploader: uploader)
        drain.start(["s"])
        drain.waitUntilSettled()
        clock.advance(to: clock.now().addingTimeInterval(1))
        drain.waitUntilSettled()
        XCTAssertEqual(uploader.requests.map(\.count), [500, 200])
        XCTAssertEqual(uploader.requests[1].map(index), Array(500..<700))
    }

    func testDrain_outOfRetrySlots_keepsTheRestForALaterLaunch_whichSendsItOnce() throws {
        let buffer = makeBuffer()
        (0..<600).forEach { buffer.hold(event($0), sessionId: "s") }
        buffer.trigger("s")
        let clock = ManualDeliveryClock()
        let failing = SpanUploadResult(disposition: .retryable, httpStatus: 503, retryAfter: nil, countsAsFailedUpload: true)
        let uploader = ScriptedUploads(script: [.delivered, failing, failing, failing])
        let drain = makeDrain(buffer, clock: clock, uploader: uploader)
        drain.start(["s"])
        drain.waitUntilSettled()
        while let next = clock.nextDate {
            clock.advance(to: next)
            drain.waitUntilSettled()
        }
        XCTAssertEqual(uploader.requests.count, 4, "First try, then the +30 s and +2 min slots, then it stops.")
        XCTAssertEqual(buffer.metadata(of: "s")?.failedUploads, 3)

        // The process is killed; the next launch adopts the buffer and sends only what is left.
        let relaunch = makeBuffer()
        let toDrain = relaunch.adoptLeftovers { $0.triggered }
        let nextUploader = ScriptedUploads()
        let nextDrain = makeDrain(relaunch, clock: clock, uploader: nextUploader)
        nextDrain.start(toDrain)
        nextDrain.waitUntilSettled()
        XCTAssertEqual(nextUploader.requests.flatMap { $0 }.map(index), Array(500..<600))
    }

    func testDrain_givesUpAfter16CountedFailures() {
        let buffer = makeBuffer()
        buffer.hold(event(0), sessionId: "s")
        buffer.trigger("s")
        (0..<CrashDeliveryScheduler.maxFailedUploads).forEach { _ in buffer.countFailedUpload(of: "s") }
        let uploader = ScriptedUploads()
        let drain = makeDrain(buffer, clock: ManualDeliveryClock(), uploader: uploader)
        drain.start(["s"])
        drain.waitUntilSettled()
        XCTAssertTrue(uploader.requests.isEmpty)
        XCTAssertNil(buffer.metadata(of: "s"), "Given up: deleted.")
    }

    func testDrain_offline_sendsNothing_andKeepsTheBuffer() {
        let buffer = makeBuffer()
        buffer.hold(event(0), sessionId: "s")
        buffer.trigger("s")
        let uploader = ScriptedUploads()
        let drain = ErrorOnlyDrain(buffer: buffer, clock: ManualDeliveryClock(), backgroundTasks: FakeBackgroundTasks(),
                                   isOnline: { false }, upload: uploader.upload)
        drain.start(["s"])
        drain.waitUntilSettled()
        XCTAssertTrue(uploader.requests.isEmpty)
        XCTAssertEqual(buffer.metadata(of: "s")?.failedUploads, 0, "Offline is not counted.")
    }

    // MARK: - Helpers

    private func makeBuffer(maxRumEvents: Int = 5_000, writer: ErrorOnlyFileWriting = PosixFileWriter()) -> ErrorOnlyBuffer {
        ErrorOnlyBuffer(maxRumEvents: maxRumEvents, directory: directory, writer: writer)
    }

    private func makeDrain(_ buffer: ErrorOnlyBuffer, clock: ManualDeliveryClock, uploader: ScriptedUploads) -> ErrorOnlyDrain {
        ErrorOnlyDrain(buffer: buffer, clock: clock, backgroundTasks: FakeBackgroundTasks(),
                       isOnline: { true }, upload: uploader.upload)
    }

    private func event(_ index: Int, padding: Int = 0) -> Data {
        let object: [String: Any] = ["i": index, "pad": String(repeating: "x", count: padding)]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private func index(_ event: [String: Any]) -> Int {
        event["i"] as? Int ?? -1
    }
}

/// Answers each upload from a script, then `.delivered`; records every request.
private final class ScriptedUploads {
    private let lock = NSLock()
    private var script: [SpanUploadResult]
    private var inFlight = 0
    private(set) var maxInFlight = 0
    private var _requests: [[[String: Any]]] = []

    init(script: [SpanUploadResult] = []) {
        self.script = script
    }

    var requests: [[[String: Any]]] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func upload(_ events: [[String: Any]]) -> SpanUploadResult {
        lock.lock()
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        _requests.append(events)
        let result = script.isEmpty ? .delivered : script.removeFirst()
        lock.unlock()
        Thread.sleep(forTimeInterval: 0.001)
        lock.lock(); inFlight -= 1; lock.unlock()
        return result
    }
}

/// Writes `failAfter` events, then fails the next write half way, as a full disk does.
private final class FailingWriter: ErrorOnlyFileWriting {
    private var remaining: Int
    private let real = PosixFileWriter()

    init(failAfter: Int) {
        self.remaining = failAfter
    }

    func append(_ data: Data, to url: URL) throws {
        guard remaining > 0 else {
            try real.append(data.prefix(data.count / 2), to: url)
            throw POSIXError(.ENOSPC)
        }
        remaining -= 1
        try real.append(data, to: url)
    }

    func truncate(_ url: URL, to length: UInt64) {
        real.truncate(url, to: length)
    }
}
