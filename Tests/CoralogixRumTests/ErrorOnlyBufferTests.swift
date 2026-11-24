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

    /// Ordinary events run a few KB; the per-session cap must not bite on them before maxRumEvents.
    func testByteCap_isReachedOnlyByEventsAveragingOver16KB() throws {

        let ordinary = makeBuffer(maxRumEvents: 3)
        (0..<3).forEach { ordinary.hold(event($0, padding: 10_000), sessionId: "s") }
        ordinary.trigger("s")
        let chunk = try XCTUnwrap(ordinary.nextChunk(of: "s", maxEvents: 500, maxBytes: ErrorOnlyDrain.maxBytesPerRequest),
                                  "10 KB events, larger than most, are kept up to maxRumEvents.")
        XCTAssertEqual(chunk.events.map(index), [0, 1, 2])

        let large = makeBuffer(maxRumEvents: 3)
        large.hold(event(0, padding: 3 * 16 * 1_024), sessionId: "s")
        XCTAssertNil(large.metadata(of: "s"), "Events averaging over 16 KB clear the buffer before maxRumEvents.")
    }

    /// At the 20000 maximum, 16 KB per event would allow 320 MB: 100 MB is the ceiling.
    func testByteCap_isAtMost100MB_evenAtTheMaximumMaxRumEvents() {
        XCTAssertEqual(makeBuffer(maxRumEvents: 5_000).maxBytes, 5_000 * ErrorOnlyBuffer.bytesPerEvent,
                       "Below the ceiling, 16 KB per event.")

        let buffer = makeBuffer(maxRumEvents: 20_000)
        XCTAssertEqual(buffer.maxBytes, 100 * 1_024 * 1_024)
        let nearlyOneMB = event(0, padding: ErrorOnlyBuffer.maxEventBytes - 100)
        let underTheCeiling = 100 * 1_024 * 1_024 / (nearlyOneMB.count + 1)
        (0..<underTheCeiling).forEach { buffer.hold(event($0, padding: ErrorOnlyBuffer.maxEventBytes - 100), sessionId: "s") }
        XCTAssertNotNil(buffer.metadata(of: "s"), "Precondition: under 100 MB the session is held.")
        buffer.hold(nearlyOneMB, sessionId: "s")
        XCTAssertNil(buffer.metadata(of: "s"), "Past 100 MB the session is cleared, though 320 MB would allow it.")
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

    // MARK: - The error that triggers a session

    func testTriggerHolding_keepsTheErrorLast_andRecordsTheTriggerOnDisk() throws {
        let buffer = makeBuffer()
        (0..<2).forEach { buffer.hold(event($0), sessionId: "s") }
        XCTAssertTrue(buffer.triggerHolding(event(99), sessionId: "s"))
        XCTAssertTrue(try savedMetadata("s").triggered)
        let chunk = try XCTUnwrap(buffer.nextChunk(of: "s", maxEvents: 500, maxBytes: ErrorOnlyDrain.maxBytesPerRequest))
        XCTAssertEqual(chunk.events.map(index), [0, 1, 99])
    }

    func testTriggerHolding_pastTheCap_stillKeepsEverything() throws {
        let buffer = makeBuffer(maxRumEvents: 2)
        (0..<2).forEach { buffer.hold(event($0), sessionId: "s") }
        XCTAssertTrue(buffer.triggerHolding(event(99), sessionId: "s"), "The error never clears what it triggers.")
        let chunk = try XCTUnwrap(buffer.nextChunk(of: "s", maxEvents: 500, maxBytes: ErrorOnlyDrain.maxBytesPerRequest))
        XCTAssertEqual(chunk.events.map(index), [0, 1, 99])
    }

    func testTriggerHolding_whenTheTriggerCannotBeSaved_takesTheErrorBackOut() throws {
        let writer = FlakyMetadataWriter()
        let buffer = makeBuffer(writer: writer)
        (0..<2).forEach { buffer.hold(event($0), sessionId: "s") }
        writer.failing = true
        XCTAssertFalse(buffer.triggerHolding(event(99), sessionId: "s"),
                       "A restart would delete it with the session: the caller sends it live.")
        XCTAssertTrue(buffer.isTriggered("s"))
        let onDisk = try String(contentsOf: directory.appendingPathComponent("s.jsonl")).split(separator: "\n")
        XCTAssertEqual(onDisk.count, 2, "Not sent a second time by the drain.")
    }

    func testTriggerHolding_afterAWriteFailed_isSentLive() {
        let buffer = makeBuffer(writer: FailingWriter(failAfter: 1))
        (0..<2).forEach { buffer.hold(event($0), sessionId: "s") }
        XCTAssertFalse(buffer.triggerHolding(event(99), sessionId: "s"), "The disk is full: sent live.")
        XCTAssertTrue(buffer.isTriggered("s"))
    }

    func testAFileThatCannotBeReadNow_isKept_notTakenForADeletedOne() throws {
        let buffer = makeBuffer()
        buffer.hold(event(0), sessionId: "s")
        buffer.trigger("s")
        let file = directory.appendingPathComponent("s.jsonl")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

        XCTAssertNil(buffer.nextChunk(of: "s", maxEvents: 500, maxBytes: ErrorOnlyDrain.maxBytesPerRequest))
        XCTAssertNotNil(buffer.metadata(of: "s"), "A session that had its error is not deleted for a failed read.")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        let chunk = try XCTUnwrap(buffer.nextChunk(of: "s", maxEvents: 500, maxBytes: ErrorOnlyDrain.maxBytesPerRequest))
        XCTAssertEqual(chunk.events.map(index), [0], "Read on a later attempt.")
    }

    func testDiscard_removesAnUntriggeredSession_butNotATriggeredOne() {
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

    func testEndedSession_keepsHoldingThroughItsGrace_thenIsDiscarded() {
        let clock = ManualDeliveryClock()
        let buffer = ErrorOnlyBuffer(maxRumEvents: 5_000, directory: directory, clock: clock)
        buffer.hold(event(0), sessionId: "a")
        buffer.endSession("a")

        clock.advance(to: clock.now().addingTimeInterval(29))
        XCTAssertTrue(buffer.isInGrace("a"))
        buffer.hold(event(1), sessionId: "a")
        XCTAssertNotNil(buffer.metadata(of: "a"), "Still held 29 s after the session ended.")

        clock.advance(to: clock.now().addingTimeInterval(2))
        XCTAssertFalse(buffer.isInGrace("a"))
        XCTAssertNil(buffer.metadata(of: "a"), "No error within the grace: deleted.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("a.jsonl").path))
        buffer.hold(event(2), sessionId: "a")
        XCTAssertNil(buffer.metadata(of: "a"), "After the grace it is never held for again.")
    }

    func testEndedSession_triggeredInItsGrace_isKeptForTheDrain() throws {
        let clock = ManualDeliveryClock()
        let buffer = ErrorOnlyBuffer(maxRumEvents: 5_000, directory: directory, clock: clock)
        buffer.hold(event(0), sessionId: "a")
        buffer.endSession("a")
        buffer.trigger("a")
        clock.advance(to: clock.now().addingTimeInterval(60))
        let chunk = try XCTUnwrap(buffer.nextChunk(of: "a", maxEvents: 500, maxBytes: ErrorOnlyDrain.maxBytesPerRequest))
        XCTAssertEqual(chunk.events.map(index), [0], "A triggered session is not touched by the grace.")
    }

    func testAfterADiscard_aLateEventOfThatSessionIsNotHeldAgain() {
        let buffer = makeBuffer()
        buffer.hold(event(0), sessionId: "a")
        buffer.discardUntriggered("a")
        XCTAssertTrue(buffer.hold(event(1), sessionId: "a"), "Handled: dropped, not sent live.")
        XCTAssertNil(buffer.metadata(of: "a"), "The ended session's buffer is not started again.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("a.jsonl").path))
    }

    func testHoldAndTriggerAtTheSameTime_everyEventIsHeldOrSentOnce() {
        let buffer = makeBuffer()
        let count = 400
        let sentLive = SentLive()
        DispatchQueue.concurrentPerform(iterations: count + 1) { i in
            if i == count / 2 {
                buffer.trigger("s")
            } else {
                let index = i > count / 2 ? i - 1 : i
                if !buffer.hold(event(index), sessionId: "s") { sentLive.add(index) }
            }
        }
        var held: [Int] = []
        while let chunk = buffer.nextChunk(of: "s", maxEvents: 500, maxBytes: ErrorOnlyDrain.maxBytesPerRequest) {
            held += chunk.events.map(index)
            buffer.commit(chunk)
        }
        XCTAssertEqual((held + sentLive.values).sorted(), Array(0..<count),
                       "Each event is either held for the drain or sent live, exactly once.")
        XCTAssertFalse(sentLive.values.isEmpty || held.isEmpty, "Precondition: the trigger landed mid-way.")
    }

    // MARK: - Leftovers

    func testLeftoverWithAnImpossibleOffset_isDeletedAsCorrupt() throws {
        let earlier = makeBuffer()
        earlier.hold(event(0), sessionId: "s")
        earlier.trigger("s")
        let metaURL = directory.appendingPathComponent("s.meta.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metaURL)) as? [String: Any])
        json["sentOffset"] = UInt64.max
        try JSONSerialization.data(withJSONObject: json).write(to: metaURL)

        let relaunch = makeBuffer()
        XCTAssertEqual(relaunch.adoptLeftovers { _ in true }, [], "Not drained: it would trap converting the offset.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: metaURL.path), "Deleted as corrupt.")
    }

    func testShutdown_keepsALeftoverWaitingForItsCrash() {
        let earlier = makeBuffer()
        earlier.hold(event(0), sessionId: "crashed")
        let relaunch = makeBuffer()
        _ = relaunch.adoptLeftovers { _ in true }
        relaunch.hold(event(1), sessionId: "own")

        relaunch.discardAllUntriggered()
        XCTAssertNotNil(relaunch.metadata(of: "crashed"), "The crash, sent later, is its trigger.")
        XCTAssertNil(relaunch.metadata(of: "own"), "This instance's own untriggered buffer goes.")
    }

    /// A buffer waiting on a crash that is never sent (a fatal hang with ANR reporting off) is only
    /// ever looked at here, so the age limit must apply here too.
    func testLeftoverPastTheAgeLimit_isDeletedAtLaunch_evenWhileWaitingForItsCrash() throws {
        let earlier = makeBuffer()
        earlier.hold(event(0), sessionId: "waiting")
        earlier.hold(event(0), sessionId: "triggered")
        earlier.trigger("triggered")

        let dayBeforeTheLimit = makeBuffer(clock: ManualDeliveryClock(start: Date().addingTimeInterval(CrashDeliveryScheduler.maxAge - 86_400)))
        _ = dayBeforeTheLimit.adoptLeftovers { _ in true }
        XCTAssertNotNil(dayBeforeTheLimit.metadata(of: "waiting"), "Precondition: within 7 days it is kept for its crash.")

        let pastTheLimit = makeBuffer(clock: ManualDeliveryClock(start: Date().addingTimeInterval(CrashDeliveryScheduler.maxAge + 60)))
        XCTAssertEqual(pastTheLimit.adoptLeftovers { _ in true }, [], "Past 7 days nothing is drained.")
        XCTAssertNil(pastTheLimit.metadata(of: "waiting"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [],
                       "Both sessions' files are deleted.")
    }

    /// An offline device leaves a session that had its error per launch: the newest 10 are kept,
    /// and a session waiting on its crash is not counted.
    func testLeftovers_onlyTheNewest10ThatHadTheirError_areKept() throws {
        let earlier = makeBuffer()
        let ids = (0...ErrorOnlyBuffer.maxLeftoverSessions).map { "triggered-\($0)" }
        for id in ids {
            earlier.hold(event(0), sessionId: id)
            earlier.trigger(id)
            Thread.sleep(forTimeInterval: 0.002)  // createdAt orders them
        }
        earlier.hold(event(0), sessionId: "crashed")

        let relaunch = makeBuffer()
        XCTAssertEqual(relaunch.adoptLeftovers { $0.triggered || $0.sessionId == "crashed" }, Array(ids.dropFirst()),
                       "The newest 10, oldest first.")
        XCTAssertNil(relaunch.metadata(of: ids[0]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(ids[0]).jsonl").path),
                       "The oldest one's files are deleted.")
        XCTAssertNotNil(relaunch.metadata(of: "crashed"), "Waiting on its crash: not counted, kept.")
    }

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

    func testDrain_stopWithARequestInFlight_cancelsIt_andKeepsTheBuffer() {
        let buffer = makeBuffer()
        (0..<10).forEach { buffer.hold(event($0), sessionId: "s") }
        buffer.trigger("s")
        let inFlight = BlockingUpload()
        let drain = ErrorOnlyDrain(buffer: buffer, clock: ManualDeliveryClock(), backgroundTasks: FakeBackgroundTasks(),
                                   isOnline: { true }, upload: inFlight.upload, cancelUpload: inFlight.cancel)
        drain.start(["s"])
        inFlight.waitUntilStarted()
        drain.stop()
        drain.waitUntilSettled()

        XCTAssertEqual(inFlight.requests, 1)
        XCTAssertEqual(buffer.metadata(of: "s")?.sentOffset, 0, "A cancelled request is not committed.")
        XCTAssertEqual(buffer.metadata(of: "s")?.failedUploads, 0, "Nor counted.")
        drain.start(["s"])
        drain.waitUntilSettled()
        XCTAssertEqual(inFlight.requests, 1, "A stopped drain sends nothing more.")
    }

    func testDrain_backgroundExpiry_resumesLater_withoutSendingAChunkTwice() {
        let buffer = makeBuffer()
        (0..<600).forEach { buffer.hold(event($0), sessionId: "s") }
        buffer.trigger("s")
        let tasks = FakeBackgroundTasks()
        let clock = ManualDeliveryClock()
        let inFlight = BlockingUpload(blockOnRequest: 2)
        let drain = ErrorOnlyDrain(buffer: buffer, clock: clock, backgroundTasks: tasks,
                                   isOnline: { true }, upload: inFlight.upload, cancelUpload: inFlight.cancel)
        drain.start(["s"])
        drain.waitUntilSettled()
        clock.advance(to: clock.now().addingTimeInterval(1))
        inFlight.waitUntilStarted()
        tasks.expireAll()
        drain.waitUntilSettled()

        drain.start(["s"])
        drain.waitUntilSettled()
        clock.advance(to: clock.now().addingTimeInterval(1))
        drain.waitUntilSettled()

        XCTAssertEqual(inFlight.deliveredIndices(index), Array(0..<600), "Every event once, in order.")
        XCTAssertNil(buffer.metadata(of: "s"))
    }

    func testUnsavedTrigger_doesNotStopTheDrain() throws {
        let writer = FlakyMetadataWriter()
        let buffer = makeBuffer(writer: writer)
        (0..<3).forEach { buffer.hold(event($0), sessionId: "s") }
        writer.failing = true
        buffer.trigger("s")
        XCTAssertEqual(try savedMetadata("s").triggered, false,
                       "Precondition: on disk the session still reads as one without an error.")

        let uploader = ScriptedUploads()
        let drain = makeDrain(buffer, clock: ManualDeliveryClock(), uploader: uploader)
        drain.start(["s"])
        drain.waitUntilSettled()
        XCTAssertEqual(uploader.requests.map { $0.map(index) }, [[0, 1, 2]],
                       "Safe to send: a restart deletes a session the disk records without an error.")
    }

    func testDiskFull_eventsHeldInMemory_areSent_thoughTheTriggerCannotBeSaved() throws {
        let writer = FlakyMetadataWriter()
        let buffer = makeBuffer(writer: writer)
        (0..<2).forEach { buffer.hold(event($0), sessionId: "s") }
        writer.failing = true
        writer.failingAppends = true
        (2..<4).forEach { buffer.hold(event($0), sessionId: "s") }
        buffer.trigger("s")

        let uploader = ScriptedUploads()
        let clock = ManualDeliveryClock()
        let drain = makeDrain(buffer, clock: clock, uploader: uploader)
        drain.start(["s"])
        drain.waitUntilSettled()
        clock.advance(to: clock.now().addingTimeInterval(1))
        drain.waitUntilSettled()
        clock.advance(to: clock.now().addingTimeInterval(1))
        drain.waitUntilSettled()
        XCTAssertEqual(uploader.requests.map { $0.map(index) }, [[0, 1], [2, 3]], "The disk part, then memory.")
        XCTAssertNil(buffer.metadata(of: "s"), "Done with.")
    }

    func testUnsavedCursorAfterTheLastChunk_stillDeletesTheBuffer_soARestartSendsNothingAgain() throws {
        let writer = FlakyMetadataWriter()
        let buffer = makeBuffer(writer: writer)
        (0..<3).forEach { buffer.hold(event($0), sessionId: "s") }
        buffer.trigger("s")
        XCTAssertEqual(try savedMetadata("s").sentOffset, 0, "Precondition: the trigger reached disk.")
        writer.failing = true

        let uploader = ScriptedUploads()
        let clock = ManualDeliveryClock()
        let drain = makeDrain(buffer, clock: clock, uploader: uploader)
        drain.start(["s"])
        drain.waitUntilSettled()
        clock.advance(to: clock.now().addingTimeInterval(1))
        drain.waitUntilSettled()

        XCTAssertEqual(uploader.requests.map { $0.map(index) }, [[0, 1, 2]])
        XCTAssertNil(buffer.metadata(of: "s"), "Everything was sent: the session is done with.")
        XCTAssertEqual(makeBuffer().adoptLeftovers { $0.triggered }, [],
                       "No file is left for a restart to send a second time.")
    }

    func testUnsavedCursorAfterTheLastChunk_deletesTheBufferAtOnce_soAKillBeforeTheNextRequestSendsNothingAgain() throws {
        let writer = FlakyMetadataWriter()
        let buffer = makeBuffer(writer: writer)
        (0..<3).forEach { buffer.hold(event($0), sessionId: "s") }
        buffer.trigger("s")
        writer.failing = true

        let uploader = ScriptedUploads()
        let clock = ManualDeliveryClock()
        let drain = makeDrain(buffer, clock: clock, uploader: uploader)
        drain.start(["s"])
        drain.waitUntilSettled()

        XCTAssertEqual(uploader.requests.map { $0.map(index) }, [[0, 1, 2]])
        XCTAssertEqual(makeBuffer().adoptLeftovers { $0.triggered }, [],
                       "The drain still waits out its gap: a restart now must find nothing to send again.")
    }

    func testUnsavedCursorBeforeMemoryEvents_deletesTheSentFile_andTheMemoryEventsStillGo() throws {
        let writer = FlakyMetadataWriter()
        let buffer = makeBuffer(writer: writer)
        (0..<2).forEach { buffer.hold(event($0), sessionId: "s") }
        writer.failingAppends = true
        buffer.hold(event(2), sessionId: "s")
        buffer.trigger("s")
        writer.failing = true

        let uploader = ScriptedUploads()
        let clock = ManualDeliveryClock()
        let drain = makeDrain(buffer, clock: clock, uploader: uploader)
        drain.start(["s"])
        drain.waitUntilSettled()
        XCTAssertEqual(makeBuffer().adoptLeftovers { $0.triggered }, [],
                       "The sent file is gone before the memory request: a restart sends it no second time.")

        clock.advance(to: clock.now().addingTimeInterval(1))
        drain.waitUntilSettled()
        XCTAssertEqual(uploader.requests.map { $0.map(index) }, [[0, 1], [2]])
        clock.advance(to: clock.now().addingTimeInterval(1))
        drain.waitUntilSettled()
        XCTAssertNil(buffer.metadata(of: "s"), "Done with.")
    }

    func testUnsavedFailureCount_keepsTheSession_andTheDrainGoesOn() throws {
        let writer = FlakyMetadataWriter()
        let buffer = makeBuffer(writer: writer)
        buffer.hold(event(0), sessionId: "s")
        buffer.trigger("s")
        writer.failing = true

        let serverError = SpanUploadResult(disposition: .retryable, httpStatus: 503, retryAfter: nil, countsAsFailedUpload: true)
        let uploader = ScriptedUploads(script: [serverError])
        let clock = ManualDeliveryClock()
        let drain = makeDrain(buffer, clock: clock, uploader: uploader)
        drain.start(["s"])
        drain.waitUntilSettled()
        XCTAssertEqual(buffer.metadata(of: "s")?.failedUploads, 1, "Counted, though the disk could not record it.")

        clock.advance(to: clock.now().addingTimeInterval(30))
        drain.waitUntilSettled()
        XCTAssertEqual(uploader.requests.map { $0.map(index) }, [[0], [0]],
                       "Retried on the next slot while the count is still unsaved, not given up.")
    }

    private func savedMetadata(_ sessionId: String) throws -> ErrorOnlyBuffer.Metadata {
        try JSONDecoder().decode(ErrorOnlyBuffer.Metadata.self,
                                 from: Data(contentsOf: directory.appendingPathComponent("\(sessionId).meta.json")))
    }

    func testUnsavedTrigger_savedOnRetry_isKeptByTheNextLaunch() {
        let writer = FlakyMetadataWriter()
        let buffer = makeBuffer(writer: writer)
        buffer.hold(event(0), sessionId: "s")
        writer.failing = true
        buffer.trigger("s")
        writer.failing = false
        XCTAssertTrue(buffer.maySend(of: "s"))

        XCTAssertEqual(makeBuffer().adoptLeftovers { $0.triggered }, ["s"],
                       "After a restart the session is still known to have had its error.")
    }

    func testUnsavedCursor_isNotPassed() throws {
        let writer = FlakyMetadataWriter()
        let buffer = makeBuffer(writer: writer)
        (0..<600).forEach { buffer.hold(event($0), sessionId: "s") }
        buffer.trigger("s")
        let clock = ManualDeliveryClock()
        let uploader = ScriptedUploads()
        let drain = makeDrain(buffer, clock: clock, uploader: uploader)
        writer.failing = true
        drain.start(["s"])
        drain.waitUntilSettled()
        clock.advance(to: clock.now().addingTimeInterval(1))
        drain.waitUntilSettled()
        XCTAssertEqual(uploader.requests.count, 1, "The second request waits for the first one's cursor to be saved.")
        XCTAssertEqual(try savedMetadata("s").sentOffset, 0, "A restart resends the first request rather than skip past it.")
        writer.failing = false
        clock.advance(to: clock.now().addingTimeInterval(30))
        drain.waitUntilSettled()
        clock.advance(to: clock.now().addingTimeInterval(1))
        drain.waitUntilSettled()
        XCTAssertEqual(uploader.requests.flatMap { $0 }.map(index), Array(0..<600), "Then it goes on, nothing twice.")
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

    // MARK: - Test hooks

    /// Unlocked, a read racing a write over-releases the clock it loads and crashes the process.
    func testTestHooks_concurrentReadsAndWrites_doNotRace() {
        DispatchQueue.concurrentPerform(iterations: 20_000) { index in
            if index.isMultiple(of: 2) {
                ErrorOnlyBuffer.testClock = ManualDeliveryClock()
                ErrorOnlyBuffer.testDirectory = URL(fileURLWithPath: "/hooks/\(index)")
            } else {
                _ = ErrorOnlyBuffer.defaultClock.now()
                _ = ErrorOnlyBuffer.defaultDirectory.path
            }
        }
        ErrorOnlyBuffer.testClock = nil
        ErrorOnlyBuffer.testDirectory = nil
        XCTAssertTrue(ErrorOnlyBuffer.defaultClock is SystemDeliveryClock)
        XCTAssertEqual(ErrorOnlyBuffer.defaultDirectory.lastPathComponent, "error-only")
    }

    // MARK: - Helpers

    private func makeBuffer(maxRumEvents: Int = 5_000, writer: ErrorOnlyFileWriting = PosixFileWriter(),
                            clock: DeliveryClock = SystemDeliveryClock()) -> ErrorOnlyBuffer {
        ErrorOnlyBuffer(maxRumEvents: maxRumEvents, directory: directory, writer: writer, clock: clock)
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

/// Delivers every request except the `blockOnRequest`th, which waits until it is cancelled and
/// then answers `notAttempted`, as a cancelled URLSession task does.
private final class BlockingUpload {
    private let lock = NSLock()
    private let started = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private let blockOnRequest: Int
    private var count = 0
    private var delivered: [[[String: Any]]] = []

    init(blockOnRequest: Int = 1) {
        self.blockOnRequest = blockOnRequest
    }

    var requests: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func deliveredIndices(_ index: ([String: Any]) -> Int) -> [Int] {
        lock.lock(); defer { lock.unlock() }
        return delivered.flatMap { $0.map(index) }
    }

    func upload(_ events: [[String: Any]]) -> SpanUploadResult {
        lock.lock()
        count += 1
        let blocks = count == blockOnRequest
        lock.unlock()
        guard blocks else {
            lock.lock(); delivered.append(events); lock.unlock()
            return .delivered
        }
        started.signal()
        release.wait()
        return .notAttempted
    }

    func waitUntilStarted() {
        _ = started.wait(timeout: .now() + 5)
    }

    func cancel() {
        release.signal()
    }
}

private final class SentLive {
    private let lock = NSLock()
    private var _values: [Int] = []
    var values: [Int] {
        lock.lock(); defer { lock.unlock() }
        return _values
    }
    func add(_ value: Int) {
        lock.lock(); defer { lock.unlock() }
        _values.append(value)
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

    func replace(_ url: URL, with data: Data) throws {
        try real.replace(url, with: data)
    }
}

/// Fails every metadata write while `failing` is set, and every append while `failingAppends` is,
/// as a full disk would.
private final class FlakyMetadataWriter: ErrorOnlyFileWriting {
    private let lock = NSLock()
    private var _failing = false
    private var _failingAppends = false
    private let real = PosixFileWriter()
    var failing: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _failing }
        set { lock.lock(); defer { lock.unlock() }; _failing = newValue }
    }
    var failingAppends: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _failingAppends }
        set { lock.lock(); defer { lock.unlock() }; _failingAppends = newValue }
    }

    func append(_ data: Data, to url: URL) throws {
        if failingAppends { throw POSIXError(.ENOSPC) }
        try real.append(data, to: url)
    }
    func truncate(_ url: URL, to length: UInt64) { real.truncate(url, to: length) }
    func replace(_ url: URL, with data: Data) throws {
        if failing && url.lastPathComponent.hasSuffix(".meta.json") { throw POSIXError(.ENOSPC) }
        try real.replace(url, with: data)
    }
}
