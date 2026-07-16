//
//  CrashInstrumentationTests.swift
//
//
//  Created by Coralogix DEV TEAM on 16/07/2026.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class CrashInstrumentationTests: XCTestCase {
    private var options: CoralogixExporterOptions!

    override func setUpWithError() throws {
        options = CoralogixExporterOptions(
            coralogixDomain: CoralogixDomain.US2,
            userContext: nil,
            environment: "PROD",
            application: "TestApp-Crash",
            version: "1.0",
            publicKey: "token",
            sessionSampleRate: 100,
            debug: true
        )
    }

    override func tearDownWithError() throws {
        CoralogixRum.isInitialized = false
        options = nil
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    // A crash is recorded on the *next* launch, where the live view is empty this early in
    // init — so makeSpan freezes the empty sentinel onto the crash span. The span must be
    // corrected to the screen the app was on when it crashed (recovered from the keychain
    // into prevViewName), otherwise the crash reports an empty view_context.
    func test_overrideViewForCrashedSession_stampsCrashTimeView_overBlankRelaunchView() throws {
        let rum = CoralogixRum(options: options)
        let viewManager = try XCTUnwrap(rum.coralogixExporter?.getViewManager())

        let span = rum.makeSpan(event: .error, source: .console, severity: .error)
        XCTAssertEqual(frozenViewName(of: span), Keys.undefined.rawValue,
                       "precondition: a relaunch crash span starts with the empty frozen view")

        // The crashed session's last screen, recovered from the keychain at ViewManager init.
        viewManager.prevViewName = "CheckoutBeforeCrash"

        rum.overrideViewForCrashedSession(on: span)

        XCTAssertEqual(frozenViewName(of: span), "CheckoutBeforeCrash",
                       "crash span must report the crash-time view, not the blank relaunch view")
    }

    // No screen was ever shown in the crashed session (crash before first appear): there is
    // nothing to recover, so the empty frozen view is left untouched rather than invented.
    func test_overrideViewForCrashedSession_noPrevView_keepsEmptyFrozenView() throws {
        let rum = CoralogixRum(options: options)
        let viewManager = try XCTUnwrap(rum.coralogixExporter?.getViewManager())
        viewManager.prevViewName = nil

        let span = rum.makeSpan(event: .error, source: .console, severity: .error)
        rum.overrideViewForCrashedSession(on: span)

        XCTAssertEqual(frozenViewName(of: span), Keys.undefined.rawValue,
                       "with no crash-time view on record, the empty frozen view is left untouched")
    }

    private func frozenViewName(of span: any Span) -> String? {
        guard let data = (span as? any ReadableSpan)?.toSpanData() else { return nil }
        return data.attributes[Keys.spanViewName.rawValue]?.description
    }
}
