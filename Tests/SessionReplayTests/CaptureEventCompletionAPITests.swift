//
//  CaptureEventCompletionAPITests.swift
//  Session-Replay-Tests
//
//  Guards the completion overload's compile surface from outside the module. This file
//  deliberately imports only SessionReplay — no CoralogixInternal, no @testable — so it fails
//  to compile if reading the outcome starts requiring a second import. The overload is wiring
//  for the SDK's own spans and is deliberately not documented for customers, so this file is
//  the only thing pinning what a caller outside the module needs in scope.
//

import XCTest
import SessionReplay

final class CaptureEventCompletionAPITests: XCTestCase {

    /// Compile-surface check, not a behaviour test. It asserts only that the call resolves from
    /// a single `import SessionReplay` and that the completion is reached at all —
    /// `SessionReplay.shared` is a process-wide singleton other files in this target initialise,
    /// so which branch of the switch it lands in depends on test ordering and is not asserted.
    /// Single-invocation and the per-outcome behaviour are covered honestly in
    /// `CaptureCompletionOutcomeTests` and `FlutterViewDropOnNilTests`.
    func testCaptureEventCompletion_isReachableFromAConsumerImportSurface() {
        let answered = expectation(description: "completion called")
        var reached = false

        // No error type is named, so no second import is needed to read the outcome.
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
