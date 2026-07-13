//
//  StackTraceTruncationTests.swift
//
//  Covers CX-48437 — native-crash stack-trace truncation: middle-out frame truncation,
//  frame-cap flooring, and the contiguous-prefix thread retention + deterministic byte guard.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class StackTraceTruncationTests: XCTestCase {

    // MARK: - Helpers

    /// A synthetic thread of `count` frames; `binary` is tagged "T<id>" so the thread is
    /// identifiable after serialization, and `frame_number` runs 0..<count.
    private func makeThread(id: Int, frames count: Int) -> [[String: Any]] {
        (0..<count).map { i in
            [
                Keys.frameNumber.rawValue: "\(i)",
                Keys.binary.rawValue: "T\(id)",
                Keys.functionAddressCalled.rawValue: "0x000000010000\(String(format: "%04x", i))",
                Keys.base.rawValue: "symbol_\(i)",
                Keys.offset.rawValue: "\(i * 7)"
            ]
        }
    }

    /// Decodes the `threads` attribute (JSON array of per-thread JSON strings) back into frames.
    private func decodeThreads(_ json: String) -> [[[String: Any]]] {
        guard let data = json.data(using: .utf8),
              let threadStrings = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return threadStrings.compactMap { threadString in
            guard let d = threadString.data(using: .utf8),
                  let frames = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return nil }
            return frames
        }
    }

    private func binaryTag(_ frames: [[String: Any]]) -> String? {
        frames.first?[Keys.binary.rawValue] as? String
    }

    // MARK: - truncateMiddleOut

    func test_truncateMiddleOut_keepsAllWhenUnderCap() {
        let frames = Array(0..<10)
        XCTAssertEqual(Helper.truncateMiddleOut(frames, cap: 20), frames)
    }

    func test_truncateMiddleOut_keepsAllWhenExactlyCap() {
        let frames = Array(0..<20)
        XCTAssertEqual(Helper.truncateMiddleOut(frames, cap: 20), frames)
    }

    func test_truncateMiddleOut_keepsHead75TailForCap20() {
        let frames = Array(0..<2000)
        let out = Helper.truncateMiddleOut(frames, cap: 20)
        XCTAssertEqual(out.count, 20)
        // head = round(0.75 * 20) = 15 → 0...14, tail = 5 → 1995...1999
        XCTAssertEqual(Array(out.prefix(15)), Array(0...14))
        XCTAssertEqual(Array(out.suffix(5)), Array(1995...1999))
        // the jump from 14 -> 1995 (a gap in frame numbers) is the self-describing "dropped" signal
        XCTAssertEqual(out[14], 14)
        XCTAssertEqual(out[15], 1995)
    }

    func test_truncateMiddleOut_nonZeroFloorSplit() {
        // cap 4: head = round(3.0) = 3, tail = 1
        let out = Helper.truncateMiddleOut(Array(0..<100), cap: 4)
        XCTAssertEqual(out, [0, 1, 2, 99])
    }

    func test_truncateMiddleOut_capZeroOrNegativeReturnsInput() {
        let frames = Array(0..<10)
        XCTAssertEqual(Helper.truncateMiddleOut(frames, cap: 0), frames)
        XCTAssertEqual(Helper.truncateMiddleOut(frames, cap: -3), frames)
    }

    // MARK: - Options clamping

    private func options(framesPerThread: Int? = nil) -> CoralogixExporterOptions {
        CoralogixExporterOptions(
            coralogixDomain: .US2,
            environment: "PROD",
            application: "TestApp-iOS",
            version: "1.0",
            publicKey: "token",
            maxStackTraceFramesPerThread: framesPerThread ?? CoralogixExporterOptions.defaultMaxStackTraceFramesPerThread
        )
    }

    func test_options_defaults() {
        XCTAssertEqual(options().maxStackTraceFramesPerThread, 20)
    }

    func test_options_framesPerThread_flooredAtOne() {
        XCTAssertEqual(options(framesPerThread: 0).maxStackTraceFramesPerThread, 1)
        XCTAssertEqual(options(framesPerThread: -9).maxStackTraceFramesPerThread, 1)
    }

    // MARK: - buildTruncatedThreads: threads

    func test_underBudget_keepsAllThreadsInOrder() {
        // Ample budget → the byte guard drops nothing: every thread is kept, in report order.
        let all = (0..<5).map { makeThread(id: $0, frames: 10) }
        let json = Helper.buildTruncatedThreads(allFrames: all, crashedIndex: 0,
                                                frameCap: 20, byteBudget: 1_000_000)
        let decoded = decodeThreads(json)
        XCTAssertEqual(decoded.map { binaryTag($0) }, ["T0", "T1", "T2", "T3", "T4"])
        XCTAssertEqual(decoded[0].count, 10) // under frame cap → untouched
    }

    func test_byteGuard_neverDropsBelowCrashedThreadPrefix() {
        // crashed thread at index 3; under byte pressure the guard drops only tail threads and
        // never reorders, so the contiguous prefix through the crashed thread (T0…T3) is retained.
        let all = (0..<8).map { makeThread(id: $0, frames: 5) }
        let json = Helper.buildTruncatedThreads(allFrames: all, crashedIndex: 3,
                                                frameCap: 20, byteBudget: 3_000)
        let decoded = decodeThreads(json)
        XCTAssertLessThan(decoded.count, 8)          // guard engaged: some tail threads dropped
        XCTAssertGreaterThanOrEqual(decoded.count, 4) // never below the crashed-thread prefix
        XCTAssertEqual(Array(decoded.prefix(4)).map { binaryTag($0) }, ["T0", "T1", "T2", "T3"])
    }

    // MARK: - buildTruncatedThreads: frame truncation

    func test_frameTruncation_appliedPerThread() {
        let all = [makeThread(id: 0, frames: 100)]
        let json = Helper.buildTruncatedThreads(allFrames: all, crashedIndex: 0,
                                                frameCap: 20, byteBudget: 1_000_000)
        let decoded = decodeThreads(json)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].count, 20)
        XCTAssertEqual(decoded[0].first?[Keys.frameNumber.rawValue] as? String, "0")
        // head 15 (0...14) + tail 5 (95...99): the frame after the head is #95
        XCTAssertEqual(decoded[0][15][Keys.frameNumber.rawValue] as? String, "95")
        XCTAssertEqual(decoded[0].last?[Keys.frameNumber.rawValue] as? String, "99")
    }

    // MARK: - buildTruncatedThreads: byte guard

    func test_byteGuard_dropsTailThreadsUntilUnderBudget() {
        let all = (0..<5).map { makeThread(id: $0, frames: 30) }
        let budget = 2_500
        let json = Helper.buildTruncatedThreads(allFrames: all, crashedIndex: 0,
                                                frameCap: 20, byteBudget: budget)
        XCTAssertLessThanOrEqual(json.utf8.count, budget)
        let decoded = decodeThreads(json)
        XCTAssertGreaterThanOrEqual(decoded.count, 1)
        XCTAssertEqual(binaryTag(decoded[0]), "T0") // crashed thread never dropped
    }

    func test_byteGuard_trimsFramesWhenCrashedThreadIsLast() {
        // crashed thread is last → no tail threads may be dropped; guard must trim frames instead.
        let all = (0..<5).map { makeThread(id: $0, frames: 40) }
        let json = Helper.buildTruncatedThreads(allFrames: all, crashedIndex: 4,
                                                frameCap: 20, byteBudget: 2_000)
        let decoded = decodeThreads(json)
        XCTAssertEqual(decoded.count, 5)                  // all threads retained (crashed is last)
        XCTAssertEqual(binaryTag(decoded[4]), "T4")       // crashed thread present
        for frames in decoded {
            XCTAssertLessThanOrEqual(frames.count, 4)     // trimmed to the frame floor
        }
    }

    func test_byteGuard_emptiesContextThreadsWhenCrashedIsHighIndex() {
        // Crash on a high-index thread among many: positional alignment forces keeping 26 threads,
        // which can't fit even at the frame floor. The guard must empty the context threads (keeping
        // their positions) so the payload still fits, while the crashed thread retains its frames.
        let all = (0..<30).map { makeThread(id: $0, frames: 10) }
        let budget = 3_000
        let json = Helper.buildTruncatedThreads(allFrames: all, crashedIndex: 25,
                                                frameCap: 20, byteBudget: budget)
        XCTAssertLessThanOrEqual(json.utf8.count, budget)   // guarantee holds even in this case
        let decoded = decodeThreads(json)
        XCTAssertEqual(decoded.count, 26)                   // positions preserved through the crashed thread
        XCTAssertEqual(binaryTag(decoded[25]), "T25")       // crashed thread retained with its frames
        XCTAssertTrue(decoded[0].isEmpty)                   // a context thread emptied to fit
    }

    func test_emptyThreadsProducesEmptyArray() {
        let json = Helper.buildTruncatedThreads(allFrames: [], crashedIndex: nil,
                                                frameCap: 20, byteBudget: 9_000)
        XCTAssertTrue(decodeThreads(json).isEmpty)
    }

    // MARK: - fitCrashRecordToByteBudget (export-time, measures the assembled record)

    /// Builds a crash log record shaped like the real one: text → cx_rum → error_context → threads.
    /// `envelopePadding` simulates a large user context / labels blob inflating everything *around*
    /// the threads, which is exactly what a fixed threads-only budget could not see.
    private func crashRecord(threads: [[[String: Any]]],
                             crashedThreadIndex: Int,
                             envelopePadding: Int = 0) -> [String: Any] {
        var errorContext: [String: Any] = [
            Keys.exceptionType.rawValue: "SIGSEGV",
            Keys.triggeredByThread.rawValue: crashedThreadIndex,
            Keys.totalThreads.rawValue: threads.count,
            Keys.isCrash.rawValue: true,
            Keys.threads.rawValue: threads
        ]
        var cxRum: [String: Any] = [Keys.errorContext.rawValue: errorContext]
        if envelopePadding > 0 {
            cxRum[Keys.userContext.rawValue] = String(repeating: "x", count: envelopePadding)
        }
        return [Keys.text.rawValue: [Keys.cxRum.rawValue: cxRum]]
    }

    private func extractThreads(_ record: [String: Any]) -> [[[String: Any]]] {
        guard let text = record[Keys.text.rawValue] as? [String: Any],
              let cxRum = text[Keys.cxRum.rawValue] as? [String: Any],
              let ec = cxRum[Keys.errorContext.rawValue] as? [String: Any],
              let threads = ec[Keys.threads.rawValue] as? [[[String: Any]]] else { return [] }
        return threads
    }

    private func recordBytes(_ record: [String: Any]) -> Int {
        (try? JSONSerialization.data(withJSONObject: record)).map { $0.count } ?? -1
    }

    func test_fitRecord_underBudget_returnedUnchanged() {
        let threads = (0..<3).map { makeThread(id: $0, frames: 5) }
        let record = crashRecord(threads: threads, crashedThreadIndex: 0)
        let out = Helper.fitCrashRecordToByteBudget(record: record, crashedIndex: 0,
                                                    frameCap: 20, byteBudget: 100_000)
        XCTAssertEqual(extractThreads(out).count, 3)
        XCTAssertEqual(extractThreads(out)[0].count, 5) // nothing trimmed
    }

    func test_fitRecord_nonCrashRecord_returnedUntouched() {
        let record: [String: Any] = [
            Keys.text.rawValue: [Keys.cxRum.rawValue: [Keys.logContext.rawValue: ["message": "hello"]]]
        ]
        // Tiny budget, but no crash `threads` to trim → the record is left alone rather than mangled.
        let out = Helper.fitCrashRecordToByteBudget(record: record, crashedIndex: nil,
                                                    frameCap: 20, byteBudget: 5)
        let cxRum = (out[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any]
        XCTAssertNotNil(cxRum?[Keys.logContext.rawValue])
        XCTAssertTrue(extractThreads(out).isEmpty)
    }

    func test_fitRecord_overBudget_trimsUntilWholeRecordFits() {
        let threads = (0..<10).map { makeThread(id: $0, frames: 30) }
        let record = crashRecord(threads: threads, crashedThreadIndex: 0)
        let budget = 4_000
        XCTAssertGreaterThan(recordBytes(record), budget) // precondition: starts oversized
        let out = Helper.fitCrashRecordToByteBudget(record: record, crashedIndex: 0,
                                                    frameCap: 20, byteBudget: budget)
        XCTAssertLessThanOrEqual(recordBytes(out), budget) // the entire assembled record now fits
        XCTAssertGreaterThanOrEqual(extractThreads(out).count, 1)
        XCTAssertEqual(binaryTag(extractThreads(out)[0]), "T0") // crashed thread never dropped
    }

    func test_fitRecord_largerEnvelopeForcesMoreTrimming() {
        let threads = (0..<10).map { makeThread(id: $0, frames: 20) }
        let budget = 6_000
        let lean = Helper.fitCrashRecordToByteBudget(
            record: crashRecord(threads: threads, crashedThreadIndex: 0),
            crashedIndex: 0, frameCap: 20, byteBudget: budget)
        let fat = Helper.fitCrashRecordToByteBudget(
            record: crashRecord(threads: threads, crashedThreadIndex: 0, envelopePadding: 3_000),
            crashedIndex: 0, frameCap: 20, byteBudget: budget)
        XCTAssertLessThanOrEqual(recordBytes(lean), budget)
        XCTAssertLessThanOrEqual(recordBytes(fat), budget)
        // The only difference is envelope size. Fewer threads survive the fat envelope — proof the
        // guard responds to the real payload, not a fixed threads-only budget (Daniel's point).
        XCTAssertLessThan(extractThreads(fat).count, extractThreads(lean).count)
    }

    func test_fitRecord_retainsCrashedThreadWhenCrashedIsHighIndex() {
        let threads = (0..<8).map { makeThread(id: $0, frames: 10) }
        let record = crashRecord(threads: threads, crashedThreadIndex: 3)
        let budget = 6_000
        let out = Helper.fitCrashRecordToByteBudget(record: record, crashedIndex: 3,
                                                    frameCap: 20, byteBudget: budget)
        XCTAssertLessThanOrEqual(recordBytes(out), budget)
        XCTAssertGreaterThanOrEqual(extractThreads(out).count, 4) // prefix through the crashed thread
        XCTAssertEqual(binaryTag(extractThreads(out)[3]), "T3")   // crashed thread retained with frames
    }
}
