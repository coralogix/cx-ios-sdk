//
//  CaptureEventCompletionAPITests.swift
//  Session-Replay-Tests
//
//  Guards the completion overload's public surface as a consumer sees it. This file
//  deliberately imports only SessionReplay — no CoralogixInternal, no @testable — so it
//  fails to compile if reading the outcome starts requiring an import the README snippet
//  does not show. See the `captureEvent` section in SessionReplay/Sources/Docs/README.md.
//

import XCTest
import SessionReplay

final class CaptureEventCompletionAPITests: XCTestCase {

    /// Compile-surface check, not a behaviour test. It asserts only that the README snippet's
    /// shape resolves from a consumer's imports and that the completion is reached at all —
    /// `SessionReplay.shared` is a process-wide singleton other files in this target initialise,
    /// so which branch of the switch it lands in depends on test ordering and is not asserted.
    /// Single-invocation and the per-outcome behaviour are covered honestly in
    /// `CaptureCompletionOutcomeTests` and `FlutterViewDropOnNilTests`.
    func testCaptureEventCompletion_isReachableFromAConsumerImportSurface() {
        let answered = expectation(description: "completion called")
        var reached = false

        // The README snippet, verbatim in shape: no error type is named, so no extra import.
        SessionReplay.shared.captureEvent(properties: nil) { result in
            switch result {
            case .success, .failure:
                reached = true
            }
            answered.fulfill()
        }

        wait(for: [answered], timeout: 5)
        XCTAssertTrue(reached, "The completion must be reached with an outcome")
    }
}
