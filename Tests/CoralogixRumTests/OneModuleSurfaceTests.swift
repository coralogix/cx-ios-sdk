//
//  OneModuleSurfaceTests.swift
//  Coralogix-Rum-Tests
//
//  The SDK ships as ONE module, `Coralogix`. The types a customer (or a hybrid plugin) reaches with
//  a plain `import Coralogix` must be declared in that module, keep their names, and stay public.
//
//  This file imports the module WITHOUT `@testable`, so it stops compiling if any type or member
//  named below loses `public`, is renamed, or changes signature.
//
//  Header contract — symbols the implementation may create for this file: NONE. Every name used
//  here exists today; the move only changes the module they are declared in.
//
//  - `testCustomerTypes_areDeclaredInModuleCoralogix` — fails until the types move into `Coralogix`.
//  - `testCustomerTypes_compileThroughAPlainImport` — compiles and passes today; must keep doing so.
//  - `testSdkVersionConstant_matchesThePodspec` — passes today; the version constant must survive
//    the move exactly once and keep matching the published podspec.
//

import XCTest
import UIKit
import Coralogix

final class OneModuleSurfaceTests: XCTestCase {

    // MARK: - Declared in module `Coralogix`

    func testCustomerTypes_areDeclaredInModuleCoralogix() {
        let reflected: [String] = [
            String(reflecting: CoralogixDomain.self),
            String(reflecting: CoralogixLogSeverity.self),
            String(reflecting: ExcludableInstrumentation.self),
            String(reflecting: CoralogixEventType.self),
            String(reflecting: Keys.self),
            String(reflecting: WireValues.self),
            String(reflecting: Global.self),
            String(reflecting: Log.self),
            String(reflecting: LogLevel.self),
            String(reflecting: OSLogger.self),
            String(reflecting: NoopLogger.self),
            String(reflecting: SDKSampler.self),
            String(reflecting: HTTPMethod.self),
            String(reflecting: InteractionEventName.self),
            String(reflecting: ScrollDirection.self),
        ]
        XCTAssertEqual(reflected, [
            "Coralogix.CoralogixDomain",
            "Coralogix.CoralogixLogSeverity",
            "Coralogix.ExcludableInstrumentation",
            "Coralogix.CoralogixEventType",
            "Coralogix.Keys",
            "Coralogix.WireValues",
            "Coralogix.Global",
            "Coralogix.Log",
            "Coralogix.LogLevel",
            "Coralogix.OSLogger",
            "Coralogix.NoopLogger",
            "Coralogix.SDKSampler",
            "Coralogix.HTTPMethod",
            "Coralogix.InteractionEventName",
            "Coralogix.ScrollDirection",
        ])
    }

    // MARK: - Plain-import compile guard

    func testCustomerTypes_compileThroughAPlainImport() {
        // Every region a customer can pass to `CoralogixExporterOptions(coralogixDomain:)`.
        let domains: [CoralogixDomain] = [.EU1, .EU2, .US1, .US2, .US3, .AP1, .AP2, .AP3, .STG]
        XCTAssertEqual(domains.count, 9)
        XCTAssertEqual(CoralogixDomain(rawValue: CoralogixDomain.US2.rawValue), .US2)

        // `CoralogixRum.log(severity:message:...)` argument.
        let severities: [CoralogixLogSeverity] = [.debug, .verbose, .info, .warn, .error, .critical]
        XCTAssertEqual(severities.count, 6)

        // `CoralogixExporterOptions(excludeFromSampling:)` element; bridges build it from raw strings.
        XCTAssertEqual(ExcludableInstrumentation.allCases.count, 9)
        let mapped: CoralogixEventType = ExcludableInstrumentation.errors.eventType
        XCTAssertEqual(mapped, .error)

        // Wire keys the hybrid plugins read by name.
        let pluginKeys: [Keys] = [
            .accountId, .accountName, .anr, .application, .applicationName, .arch, .buildId,
            .collectIPData, .data, .debug, .enableSwizzling, .environment, .errorMessage, .errorType,
            .event, .excludeFromSampling, .ignoreErrors, .ignoreUrls, .instrumentations,
            .isCrash, .keyStackTrace, .labels, .message, .mobileVitals, .name,
            .obfuscated, .parentSpanId, .proxyUrl, .sessionId, .severity, .spanId,
            .stackTraceType, .swift, .traceParentInHeader, .url, .userContext, .userEmail, .userId,
            .userMetadata, .userName, .value, .version, .virt,
        ]
        XCTAssertEqual(pluginKeys.count, 43)
        let _: WireValues = .anrErrorType

        let _: String = Global.sdk.rawValue

        // Logging façade the Flutter plugin calls, and the logger types it can be pointed at.
        Log.d("plain-import guard")
        let _: Bool = Log.isDebug
        let _: CXLogger = Log.shared
        let _: CXLogger = OSLogger(subsystem: OSLogger.defaultSubsystem, category: OSLogger.defaultCategory)
        let _: CXLogger = NoopLogger()
        XCTAssertLessThan(LogLevel.debug, LogLevel.error)

        let _: Bool = SDKSampler(sampleRate: 100).shouldInitialized()
        let _: HTTPMethod = .get
        let _: InteractionEventName = .click
        let _: ScrollDirection = .up

        // Deliberate masking the React Native plugin sets and reads on native views.
        let view = UIView()
        view.cxMask = true
        XCTAssertTrue(view.cxMask)
        XCTAssertTrue(view.isInsideMaskedSubtree)
        let deliberate: ([UIWindow]?) -> [CGRect]? = UIView.deliberateMaskRects(in:)
        XCTAssertEqual(deliberate([]), [])
    }

    // MARK: - One SDK version string

    func testSdkVersionConstant_matchesThePodspec() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CoralogixRumTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let podspec = try String(contentsOf: repoRoot.appendingPathComponent("Coralogix.podspec"), encoding: .utf8)

        let pattern = try NSRegularExpression(pattern: #"spec\.version\s*=\s*"([^"]+)""#)
        let range = NSRange(podspec.startIndex..., in: podspec)
        let match = try XCTUnwrap(pattern.firstMatch(in: podspec, range: range), "no spec.version in Coralogix.podspec")
        let version = try XCTUnwrap(Range(match.range(at: 1), in: podspec).map { String(podspec[$0]) })

        XCTAssertEqual(Global.sdk.rawValue, version)
    }
}
