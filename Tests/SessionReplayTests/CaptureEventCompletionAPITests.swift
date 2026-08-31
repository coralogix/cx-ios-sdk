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

    func testCaptureEventCompletion_isCallableAndAnswersExactlyOnce() {
        let answered = expectation(description: "completion called")
        answered.assertForOverFulfill = true
        var answers = 0

        // The README snippet, verbatim in shape: no error type is named, so no extra import.
        SessionReplay.shared.captureEvent(properties: nil) { result in
            answers += 1
            switch result {
            case .success:
                break
            case .failure(let error):
                XCTAssertFalse("\(error)".isEmpty, "The failure must describe itself to a consumer")
            }
            answered.fulfill()
        }

        wait(for: [answered], timeout: 5)
        XCTAssertEqual(answers, 1, "The completion must fire exactly once per capture")
    }
}
