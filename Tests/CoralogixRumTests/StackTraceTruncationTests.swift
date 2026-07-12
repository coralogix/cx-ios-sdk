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
}
