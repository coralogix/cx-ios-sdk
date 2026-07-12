//
//  StackTraceTruncationTests.swift
//
//  Covers CX-48437 — native-crash stack-trace truncation: middle-out frame truncation,
//  maxThreads clamping, and the contiguous-prefix thread cap + deterministic byte guard.
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

    private func options(maxThreads: Int? = nil, framesPerThread: Int? = nil) -> CoralogixExporterOptions {
        CoralogixExporterOptions(
            coralogixDomain: .US2,
            environment: "PROD",
            application: "TestApp-iOS",
            version: "1.0",
            publicKey: "token",
            maxStackTraceFramesPerThread: framesPerThread ?? CoralogixExporterOptions.defaultMaxStackTraceFramesPerThread,
            maxThreads: maxThreads ?? CoralogixExporterOptions.defaultMaxThreads
        )
    }

    func test_options_defaults() {
        let opts = options()
        XCTAssertEqual(opts.maxThreads, 2)
        XCTAssertEqual(opts.maxStackTraceFramesPerThread, 20)
    }

    func test_options_maxThreads_clampedToCeiling() {
        XCTAssertEqual(options(maxThreads: 10).maxThreads, 4)
    }

    func test_options_maxThreads_clampedToFloor() {
        XCTAssertEqual(options(maxThreads: 0).maxThreads, 1)
        XCTAssertEqual(options(maxThreads: -5).maxThreads, 1)
    }

    func test_options_framesPerThread_flooredAtOne() {
        XCTAssertEqual(options(framesPerThread: 0).maxStackTraceFramesPerThread, 1)
        XCTAssertEqual(options(framesPerThread: -9).maxStackTraceFramesPerThread, 1)
    }

    // MARK: - buildTruncatedThreads: thread cap

    func test_threadCap_keepsMaxThreadsWhenCrashedIsFirst() {
        let all = (0..<5).map { makeThread(id: $0, frames: 10) }
        let json = Helper.buildTruncatedThreads(allFrames: all, crashedIndex: 0,
                                                maxThreads: 2, frameCap: 20, byteBudget: 1_000_000)
        let decoded = decodeThreads(json)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(binaryTag(decoded[0]), "T0")
        XCTAssertEqual(binaryTag(decoded[1]), "T1")
        XCTAssertEqual(decoded[0].count, 10) // under frame cap → untouched
    }

    func test_threadCap_extendsPrefixToIncludeCrashedThread() {
        // crashed thread at index 3, maxThreads 2 → contiguous prefix must reach index 3.
        let all = (0..<6).map { makeThread(id: $0, frames: 8) }
        let json = Helper.buildTruncatedThreads(allFrames: all, crashedIndex: 3,
                                                maxThreads: 2, frameCap: 20, byteBudget: 1_000_000)
        let decoded = decodeThreads(json)
        XCTAssertEqual(decoded.count, 4)
        XCTAssertEqual(binaryTag(decoded[3]), "T3") // crashed thread present at its original position
    }

    func test_threadOrder_isNeverChanged() {
        let all = (0..<3).map { makeThread(id: $0, frames: 5) }
        let json = Helper.buildTruncatedThreads(allFrames: all, crashedIndex: 0,
                                                maxThreads: 4, frameCap: 20, byteBudget: 1_000_000)
        let decoded = decodeThreads(json)
        XCTAssertEqual(decoded.map { binaryTag($0) }, ["T0", "T1", "T2"])
    }

    // MARK: - buildTruncatedThreads: frame truncation

    func test_frameTruncation_appliedPerThread() {
        let all = [makeThread(id: 0, frames: 100)]
        let json = Helper.buildTruncatedThreads(allFrames: all, crashedIndex: 0,
                                                maxThreads: 1, frameCap: 20, byteBudget: 1_000_000)
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
                                                maxThreads: 4, frameCap: 20, byteBudget: budget)
        XCTAssertLessThanOrEqual(json.utf8.count, budget)
        let decoded = decodeThreads(json)
        XCTAssertGreaterThanOrEqual(decoded.count, 1)
        XCTAssertEqual(binaryTag(decoded[0]), "T0") // crashed thread never dropped
    }

    func test_byteGuard_trimsFramesWhenCrashedThreadIsLast() {
        // crashed thread is last → no tail threads may be dropped; guard must trim frames instead.
        let all = (0..<5).map { makeThread(id: $0, frames: 40) }
        let json = Helper.buildTruncatedThreads(allFrames: all, crashedIndex: 4,
                                                maxThreads: 2, frameCap: 20, byteBudget: 2_000)
        let decoded = decodeThreads(json)
        XCTAssertEqual(decoded.count, 5)                  // all threads retained (crashed is last)
        XCTAssertEqual(binaryTag(decoded[4]), "T4")       // crashed thread present
        for frames in decoded {
            XCTAssertLessThanOrEqual(frames.count, 4)     // trimmed to the frame floor
        }
    }

    func test_emptyThreadsProducesEmptyArray() {
        let json = Helper.buildTruncatedThreads(allFrames: [], crashedIndex: nil,
                                                maxThreads: 2, frameCap: 20, byteBudget: 9_000)
        XCTAssertTrue(decodeThreads(json).isEmpty)
    }
}
