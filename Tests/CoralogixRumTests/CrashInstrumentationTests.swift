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
    // corrected to the screen the crashed session's record holds, otherwise the crash reports an
    // empty view_context.
    func test_attributeCrashedSession_stampsTheRecordedView_overBlankRelaunchView() throws {
        let rum = CoralogixRum(options: options)

        let span = rum.makeSpan(event: .error, source: .console, severity: .error)
        XCTAssertEqual(frozenViewName(of: span), Keys.undefined.rawValue,
                       "precondition: a relaunch crash span starts with the empty frozen view")

        let record = SessionSnapshotRecord(sessionId: "crashed", errorCount: 0, viewCount: 1, actionCount: 0,
                                           hasRecording: false, viewName: "CheckoutBeforeCrash", viewNumber: 0)
        rum.attribute(span, to: .fixture(counters: record))

        XCTAssertEqual(frozenViewName(of: span), "CheckoutBeforeCrash",
                       "crash span must report the crash-time view, not the blank relaunch view")
    }

    // No screen was ever shown in the crashed session (crash before first appear): there is
    // nothing to recover, so the view stays empty rather than borrowed from the keychain's
    // last screen, which can belong to another session.
    func test_attributeCrashedSession_noRecordedView_keepsEmptyView() throws {
        let rum = CoralogixRum(options: options)
        rum.coralogixExporter?.getViewManager().prevViewName = "ScreenOfAnotherSession"

        let span = rum.makeSpan(event: .error, source: .console, severity: .error)
        rum.attribute(span, to: .fixture())

        XCTAssertEqual(frozenViewName(of: span), Keys.undefined.rawValue,
                       "with no crash-time view on record, the view is left empty")
    }

    private func frozenViewName(of span: any Span) -> String? {
        guard let data = (span as? any ReadableSpan)?.toSpanData() else { return nil }
        return data.attributes[Keys.spanViewName.rawValue]?.description
    }
}
