//
//  InstrumentationGatingTests.swift
//
//  The install-time gating rule and its truth table:
//
//      enabled(i) = optOn(i) AND (sampledIn OR excludes(i))
//
//  `instrumentations` is the source of truth. `excludeFromSampling` only ever relaxes the sampling
//  condition, so it can never re-enable something the caller switched off — and it is therefore
//  unreachable while the session is sampled in.
//
//  Network is the one instrumentation with three states rather than two, because the `traceparent`
//  header and the `network-request` event are independent concerns:
//    - installed  when the event will be reported OR propagation is on
//    - reported   when optOn(network) AND (sampledIn OR excludes(network))
//
//  Asserted against `CoralogixRum.shouldInstall` and `CoralogixExporter.reportsNetworkEvents`
//  directly. Installed swizzles are global process state, so observing them yields far weaker
//  claims than resolving the decision itself.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class InstrumentationGatingTests: XCTestCase {

    private let reportable: [CoralogixExporterOptions.InstrumentationType] =
        [.lifeCycle, .errors, .mobileVitals, .anr, .network]

    override func setUp() {
        super.setUp()
        CoralogixRum.isInitialized = false
        CoralogixRum.mobileSDK = MobileSDK(sdkFramework: .swift)
    }

    private func installed(_ options: CoralogixExporterOptions,
                           sampledIn: Bool) -> Set<CoralogixExporterOptions.InstrumentationType> {
        var result: Set<CoralogixExporterOptions.InstrumentationType> = []
        for type in reportable where CoralogixRum.shouldInstall(type, options: options, sampledIn: sampledIn) {
            result.insert(type)
        }
        return result
    }

    // MARK: - Sampled in: the options map decides, exclude is inert

    func testCase1_sampledIn_noOptionsNoExclude_installsEverything() {
        let options = makeSamplingOptions(sampleRate: 100, exclude: [])

        XCTAssertEqual(installed(options, sampledIn: true), Set(reportable))
    }

    func testCase2_sampledIn_excludeChangesNothing() {
        let bare = makeSamplingOptions(sampleRate: 100, exclude: [])
        let excluded = makeSamplingOptions(sampleRate: 100, exclude: [.errors])

        XCTAssertEqual(installed(excluded, sampledIn: true), installed(bare, sampledIn: true),
                       "excludeFromSampling must be inert on a sampled-in session.")
    }

    func testCase3_sampledIn_lifeCycleOnly_excludeCannotReviveDisabledErrors() {
        var instrumentations = allInstrumentationsOff
        instrumentations[.lifeCycle] = true
        let options = makeSamplingOptions(sampleRate: 100,
                                          exclude: [.errors],
                                          instrumentations: instrumentations)

        XCTAssertEqual(installed(options, sampledIn: true), [.lifeCycle],
                       "Only lifeCycle was switched on; listing errors in excludeFromSampling must not revive it.")
    }

    func testCase4_sampledIn_allOff_installsNothingWithoutPropagation() {
        let options = makeSamplingOptions(sampleRate: 100,
                                          exclude: [.errors],
                                          instrumentations: allInstrumentationsOff)

        XCTAssertEqual(installed(options, sampledIn: true), [])
    }

    func testCase4a_sampledIn_networkOff_installsNothingEvenWithPropagationOn() {
        // instrumentations[.network] is the outer gate, matching the browser SDK: a disabled
        // instrumentation is never registered with the OTel provider, so nothing is left to inject
        // whatever traceParentInHeader says.
        var instrumentations = allInstrumentationsOff
        instrumentations[.lifeCycle] = true
        let options = makeSamplingOptions(sampleRate: 100,
                                          exclude: [],
                                          instrumentations: instrumentations,
                                          traceParentInHeader: traceParentEnabled)

        XCTAssertEqual(installed(options, sampledIn: true), [.lifeCycle],
                       "Switching network off removes the machinery entirely, header included.")
    }

    func testSampledOut_networkOn_propagationStillKeepsItInstalled() {
        // The distinction the outer gate must preserve: sampling silences reporting without
        // silencing propagation, while the caller's own switch silences both.
        let options = makeSamplingOptions(sampleRate: 0,
                                          exclude: [],
                                          traceParentInHeader: traceParentEnabled)

        XCTAssertTrue(CoralogixRum.shouldInstall(.network, options: options, sampledIn: false),
                      "A sampled-out session must keep network installed so trace context still flows.")
        XCTAssertFalse(Helper.willReportNetworkEvents(options: options, sampledIn: false),
                       "…while reporting nothing.")
    }

    func testCase4b_sampledIn_networkOffAndPropagationOff_installsNothingForNetwork() {
        // Same outcome as 4a now — kept as a distinct row because it was reached by a different
        // route before instrumentations[.network] became the outer gate.
        var instrumentations = allInstrumentationsOff
        instrumentations[.lifeCycle] = true
        let options = makeSamplingOptions(sampleRate: 100,
                                          exclude: [],
                                          instrumentations: instrumentations)

        XCTAssertEqual(installed(options, sampledIn: true), [.lifeCycle],
                       "Nothing to propagate and nothing to report, so network must not be installed.")
    }

    // MARK: - Sampled out: only excluded-and-still-enabled survives

    func testCase5_sampledOut_noExclude_onlyNetworkForPropagation() {
        let options = makeSamplingOptions(sampleRate: 0,
                                          exclude: [],
                                          traceParentInHeader: traceParentEnabled)

        XCTAssertEqual(installed(options, sampledIn: false), [.network])
        XCTAssertFalse(Helper.willReportNetworkEvents(options: options, sampledIn: false),
                       "Propagate-only: the header goes out, the event does not.")
    }

    func testCase5_sampledOut_noExcludeNoPropagation_installsNothing() {
        let options = makeSamplingOptions(sampleRate: 0, exclude: [])

        XCTAssertEqual(installed(options, sampledIn: false), [])
    }

    func testCase6_sampledOut_excludeErrors_installsErrorsAndAnrPlusNetwork() {
        let options = makeSamplingOptions(sampleRate: 0,
                                          exclude: [.errors],
                                          traceParentInHeader: traceParentEnabled)

        XCTAssertEqual(installed(options, sampledIn: false), [.errors, .anr, .network],
                       "ANR reports arrive as error events, so excluding errors must keep ANR monitoring installed too.")
    }

    func testCase7_sampledOut_excludeNetwork_reportsNetworkEvents() {
        let options = makeSamplingOptions(sampleRate: 0, exclude: [.network])

        XCTAssertEqual(installed(options, sampledIn: false), [.network])
        XCTAssertTrue(Helper.willReportNetworkEvents(options: options, sampledIn: false),
                      "With network excluded from sampling its events export, not just the header.")
    }

    func testCase7a_sampledOut_excludeCannotReviveDisabledInstrumentation() {
        var instrumentations = allInstrumentationsOff
        instrumentations[.lifeCycle] = true
        let options = makeSamplingOptions(sampleRate: 0,
                                          exclude: [.errors],
                                          instrumentations: instrumentations)

        XCTAssertEqual(installed(options, sampledIn: false), [],
                       "errors is switched off, so excluding it from sampling must not install it.")
    }

    // MARK: - The precedence itself, stated once per branch

    func testExcludeNeverOverridesAnExplicitFalse_inBothBranches() {
        let options = makeSamplingOptions(sampleRate: 0,
                                          exclude: [.errors, .network, .userInteractions, .mobileVitals],
                                          instrumentations: allInstrumentationsOff)

        for sampledIn in [true, false] {
            XCTAssertEqual(installed(options, sampledIn: sampledIn), [],
                           "Every category is excluded from sampling and every switch is off — off must win (sampledIn: \(sampledIn)).")
        }
    }

    // MARK: - userActions is deliberately not sampling-gated

    func testUserActions_installIsNotSamplingGated() {
        // Touch swizzles also feed session replay, so they are installed independently of sampling.
        // Whether a tap becomes a span is decided by Helper.shouldEmitUserActionSpan and the export
        // filter. Stopping recording for a sampled-out session is tracked separately.
        let options = makeSamplingOptions(sampleRate: 0, exclude: [])

        XCTAssertTrue(CoralogixRum.shouldInstall(.userActions, options: options, sampledIn: false))
        XCTAssertTrue(CoralogixRum.shouldInstall(.userActions, options: options, sampledIn: true))
    }

    func testUserActions_explicitFalseStillSuppressesInstallOnNative() {
        let options = makeSamplingOptions(sampleRate: 100,
                                          exclude: [],
                                          instrumentations: [.userActions: false])

        XCTAssertFalse(CoralogixRum.shouldInstall(.userActions, options: options, sampledIn: true),
                       "On a native app the option still governs the swizzles.")
    }

    // MARK: - enableSwizzling remains a hard kill switch

    func testEnableSwizzlingFalse_installsNoURLSessionInstrumentationEvenWithPropagationOn() {
        // `shouldInstall` deliberately does not consult `enableSwizzling` — the flag is enforced
        // inside `initializeNetworkInstrumentation`, so it cannot be bypassed by the install rule.
        // Asserted through the instrumentation object, which is only created once the flag passes.
        let killed = CoralogixRum(options: makeSamplingOptions(sampleRate: 100,
                                                               exclude: [.network],
                                                               traceParentInHeader: traceParentEnabled,
                                                               enableSwizzling: false))
        defer { killed.shutdown() }

        XCTAssertNil(killed.sessionInstrumentation,
                     "enableSwizzling: false must leave NSURLSession untouched, whatever sampling and propagation ask for.")
    }

    func testEnableSwizzlingTrue_installsURLSessionInstrumentation() {
        // Positive control, so the assertion above cannot pass because the object is never built.
        let live = CoralogixRum(options: makeSamplingOptions(sampleRate: 100,
                                                            exclude: [],
                                                            traceParentInHeader: traceParentEnabled))
        defer { live.shutdown() }

        XCTAssertNotNil(live.sessionInstrumentation,
                        "With swizzling allowed the URLSession instrumentation must exist.")
    }

    // MARK: - Propagation predicate

    func testIsTraceParentInHeaderEnabled_readsTheEnableFlag() {
        XCTAssertFalse(Helper.isTraceParentInHeaderEnabled(
            options: makeSamplingOptions(sampleRate: 100, exclude: [])))
        XCTAssertFalse(Helper.isTraceParentInHeaderEnabled(
            options: makeSamplingOptions(sampleRate: 100, exclude: [],
                                         traceParentInHeader: [Keys.enable.rawValue: false])))
        XCTAssertTrue(Helper.isTraceParentInHeaderEnabled(
            options: makeSamplingOptions(sampleRate: 100, exclude: [],
                                         traceParentInHeader: traceParentEnabled)))
    }

    // MARK: - The mapping is total

    func testEveryExcludableMapsToInstrumentationTypes() {
        // Fails loudly if a case is added to ExcludableInstrumentation without deciding which
        // installers it implies. The three API-only categories map to nothing by design.
        let apiOnly: Set<ExcludableInstrumentation> = [.logs, .customSpan, .customMeasurement]

        for excludable in ExcludableInstrumentation.allCases {
            if apiOnly.contains(excludable) {
                XCTAssertTrue(excludable.instrumentationTypes.isEmpty,
                              "\(excludable) reaches the tracer through public API, so it needs no installer.")
            } else {
                XCTAssertFalse(excludable.instrumentationTypes.isEmpty,
                               "\(excludable) has no instrumentationTypes mapping.")
            }
        }
    }
}
