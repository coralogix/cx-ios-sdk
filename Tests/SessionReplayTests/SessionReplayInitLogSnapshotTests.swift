//
//  SessionReplayInitLogSnapshotTests.swift
//
//  Locks down the session-replay init-log snapshot (CX-44984): every user-configurable field,
//  defaults and custom values, the closure reduced to a presence flag, and the deprecated
//  capture interval excluded. Adding a SessionReplayOptions field should force a change here.
//

import XCTest
@testable import CoralogixInternal
@testable import SessionReplay

final class SessionReplayInitLogSnapshotTests: XCTestCase {

    func testSnapshot_defaults() {
        let snapshot = SessionReplayOptions().toSessionReplayInitLogSnapshot()

        XCTAssertEqual(snapshot[Keys.srRecordingType.rawValue] as? String, Keys.image.rawValue)
        XCTAssertEqual(snapshot[Keys.srCaptureScale.rawValue] as? Double, 2.0)
        XCTAssertEqual(snapshot[Keys.srCaptureCompressQuality.rawValue] as? Double, 1.0)
        XCTAssertEqual(snapshot[Keys.srSessionRecordingSampleRate.rawValue] as? Int, 100)
        XCTAssertEqual(snapshot[Keys.srAutoStartSessionRecording.rawValue] as? Bool, false)
        XCTAssertEqual(snapshot[Keys.srTextsToMask.rawValue] as? [String], [])
        XCTAssertEqual(snapshot[Keys.srMaskAllImages.rawValue] as? Bool, true)
        XCTAssertEqual(snapshot[Keys.srMaskOnlyCreditCards.rawValue] as? Bool, false)
        XCTAssertEqual(snapshot[Keys.srMaskFaces.rawValue] as? Bool, false)
        XCTAssertEqual(snapshot[Keys.srCreditCardPredicate.rawValue] as? [String], [])
        XCTAssertEqual(snapshot[Keys.srHasFlutterViewBitmapProvider.rawValue] as? Bool, false)
    }

    func testSnapshot_customValues() {
        let options = SessionReplayOptions(
            recordingType: .video,
            captureScale: 1.0,
            captureCompressionQuality: 0.5,
            sessionRecordingSampleRate: 42,
            maskText: ["password", "ssn"],
            maskOnlyCreditCards: true,
            maskAllImages: false,
            maskFaces: true,
            creditCardPredicate: ["card"],
            autoStartSessionRecording: true,
            flutterViewBitmapProvider: { _, _, completion in completion(nil) }
        )

        let snapshot = options.toSessionReplayInitLogSnapshot()

        XCTAssertEqual(snapshot[Keys.srRecordingType.rawValue] as? String, Keys.video.rawValue)
        XCTAssertEqual(snapshot[Keys.srCaptureScale.rawValue] as? Double, 1.0)
        XCTAssertEqual(snapshot[Keys.srCaptureCompressQuality.rawValue] as? Double, 0.5)
        XCTAssertEqual(snapshot[Keys.srSessionRecordingSampleRate.rawValue] as? Int, 42)
        XCTAssertEqual(snapshot[Keys.srAutoStartSessionRecording.rawValue] as? Bool, true)
        XCTAssertEqual(snapshot[Keys.srTextsToMask.rawValue] as? [String], ["password", "ssn"])
        XCTAssertEqual(snapshot[Keys.srMaskAllImages.rawValue] as? Bool, false)
        XCTAssertEqual(snapshot[Keys.srMaskOnlyCreditCards.rawValue] as? Bool, true)
        XCTAssertEqual(snapshot[Keys.srMaskFaces.rawValue] as? Bool, true)
        XCTAssertEqual(snapshot[Keys.srCreditCardPredicate.rawValue] as? [String], ["card"])
    }

    func testSnapshot_flutterProviderReducedToPresenceFlag() {
        let withProvider = SessionReplayOptions(flutterViewBitmapProvider: { _, _, completion in completion(nil) })
            .toSessionReplayInitLogSnapshot()
        XCTAssertEqual(withProvider[Keys.srHasFlutterViewBitmapProvider.rawValue] as? Bool, true)

        // The closure itself must never be serialised — only the boolean presence flag.
        XCTAssertTrue(JSONSerialization.isValidJSONObject(withProvider),
                      "Snapshot must be JSON-serialisable — no closures or non-JSON types leak in.")
    }

    func testSnapshot_excludesDeprecatedCaptureInterval() {
        // captureTimeInterval is deprecated and not user-tunable — it must never appear in the payload,
        // even when an old caller sets it via the deprecated initializer.
        let options = SessionReplayOptions(captureTimeInterval: 5.0)
        let snapshot = options.toSessionReplayInitLogSnapshot()

        XCTAssertFalse(snapshot.keys.contains("captureTimeInterval"))
        XCTAssertFalse(snapshot.values.contains { ($0 as? Double) == 5.0 })
    }
}
