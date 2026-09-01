//
//  TapTimestampTests.swift
//  Coralogix-Rum-Tests
//
//  A tap capture hands the Flutter bitmap provider the tap's own time so Dart can decline to
//  draw a tap it is already too late to represent. That only works if the value describes the
//  touch rather than whatever happened later in the pipeline, so these tests pin the value to
//  the touch's clock and check it survives into the capture properties.
//

import XCTest
import UIKit
import CoralogixInternal
@testable import Coralogix

final class TapTimestampTests: XCTestCase {

    // MARK: - Rebasing the touch clock

    /// `UITouch.timestamp` counts from boot, not from the epoch, so it cannot be used directly.
    func testEpochSeconds_rebasesTheTouchUptimeOntoTheEpoch() {
        let now = Date().timeIntervalSince1970
        let uptime = ProcessInfo.processInfo.systemUptime

        let rebased = TouchEvent.epochSeconds(ofTouchAt: uptime)

        XCTAssertEqual(rebased, now, accuracy: 1.0,
                       "A touch happening now must rebase to roughly now, not to seconds-since-boot")
        XCTAssertGreaterThan(rebased, 1_600_000_000,
                             "An epoch timestamp is far larger than any plausible uptime")
    }

    func testEpochSeconds_datesAnOlderTouchEarlier() {
        let uptime = ProcessInfo.processInfo.systemUptime

        let recent = TouchEvent.epochSeconds(ofTouchAt: uptime)
        let halfSecondAgo = TouchEvent.epochSeconds(ofTouchAt: uptime - 0.5)

        XCTAssertEqual(recent - halfSecondAgo, 0.5, accuracy: 0.2,
                       "A touch half a second older must date half a second earlier")
    }

    /// A touch cannot be in the future; clamping keeps a clock adjustment from producing one.
    func testEpochSeconds_doesNotDateATouchInTheFuture() {
        let uptime = ProcessInfo.processInfo.systemUptime

        let rebased = TouchEvent.epochSeconds(ofTouchAt: uptime + 60)

        XCTAssertLessThanOrEqual(rebased, Date().timeIntervalSince1970 + 0.1,
                                 "A touch must never be dated ahead of now")
    }

    // MARK: - The position-only init, which the tap path uses

    /// `Swizzle`'s `.tap` branches build a TouchEvent from the location recorded at `.began`,
    /// because UIKit may clear `touch.view` before `.ended` is delivered. They still hold the
    /// touch, so the time has to come from it — a fresh `Date()` there dates the tap at whenever
    /// the swizzle happened to run and defeats the staleness check.
    func testPositionOnlyInit_prefersTheTouchTimeOverNow() {
        let view = UIView()
        let uptime = ProcessInfo.processInfo.systemUptime - 2.0

        let withTouchTime = TouchEvent(view: view, location: .zero, eventType: .click,
                                       touchUptime: uptime)

        XCTAssertEqual(withTouchTime.timestamp,
                       Date().timeIntervalSince1970 - 2.0, accuracy: 0.3,
                       "The tap must be dated two seconds ago, not now")
    }

    func testPositionOnlyInit_fallsBackToNowWithoutATouch() {
        let event = TouchEvent(view: UIView(), location: .zero, eventType: .swipe)

        XCTAssertEqual(event.timestamp, Date().timeIntervalSince1970, accuracy: 1.0,
                       "With no touch behind it, the recogniser's own firing time is the best available")
    }

    // MARK: - Reaching the capture properties

    func testExtract_carriesTheTapTimestampForTheCaptureToRead() throws {
        let view = UIView()
        let uptime = ProcessInfo.processInfo.systemUptime - 1.0
        let event = TouchEvent(view: view, location: .zero, eventType: .click,
                               touchUptime: uptime)

        let tapData = TapDataExtractor.extract(from: event)

        let carried = try XCTUnwrap(tapData[Keys.tapTimestamp.rawValue] as? TimeInterval,
                                    "The capture properties must carry the tap time")
        XCTAssertEqual(carried, event.timestamp, accuracy: 0.001,
                       "The value must be the event's own timestamp, unmodified")
    }

    /// It has to be its own key: every capture overwrites `timestamp` with its own wall clock on
    /// the way through `SessionReplay.captureEvent`, which is what made the value useless before.
    func testExtract_usesAKeyTheCaptureDoesNotOverwrite() {
        let event = TouchEvent(view: UIView(), location: .zero, eventType: .click,
                               touchUptime: ProcessInfo.processInfo.systemUptime)

        let tapData = TapDataExtractor.extract(from: event)

        XCTAssertNotEqual(Keys.tapTimestamp.rawValue, Keys.timestamp.rawValue)
        XCTAssertNotNil(tapData[Keys.tapTimestamp.rawValue])
    }
}
