//
//  TimeMeasurementDemoModel.swift
//  DemoApp
//
//  Shared view-model behind both Time Measurement screens (UIKit + SwiftUI).
//  Owns the user-edited timer name + labels, the set of in-flight timer names,
//  and the captured `custom-measurement` spans observed via the tracesExporter.
//  SwiftUI consumes this via @ObservedObject; UIKit subscribes to objectWillChange.
//
//  Modeled on LogSamplingDemoModel — Apply rebuilds the SDK with tracesExporter
//  wired in so the captured list reflects what the SDK actually emitted (not just
//  what we asked it to emit locally).
//

import Foundation
import Combine
import Coralogix
import CoralogixInternal

struct CapturedTimeMeasurement: Identifiable {
    let id = UUID()
    let name: String
    let durationMs: Double?
    let labels: [String: Any]?
    let receivedAt: Date

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: receivedAt)
    }

    var durationString: String {
        guard let durationMs = durationMs else { return "—" }
        return String(format: "%.1f ms", durationMs)
    }

    var labelsString: String {
        guard let labels = labels, !labels.isEmpty else { return "" }
        return labels
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")
    }
}

final class TimeMeasurementDemoModel: ObservableObject {
    static let shared = TimeMeasurementDemoModel()

    /// Manual section inputs — bound to TextFields. Labels use "k=v, k=v" syntax.
    @Published var timerName: String = "checkout"
    @Published var labelsText: String = ""

    /// Timer names currently in-flight (started but not yet ended). Helps the UI show
    /// the user which timers are pending end, since startTimeMeasure has no return value.
    @Published var inFlight: Set<String> = []

    @Published var isApplied: Bool = false
    @Published var captured: [CapturedTimeMeasurement] = []

    /// Bumped on every Apply / Clear. Each tracesExporter closure captures its token so
    /// late callbacks from a previous run (still possibly in flight on the
    /// BatchSpanProcessor's queue) are discarded by the closure's token guard rather
    /// than re-filling the just-cleared list.
    private var runToken: Int = 0

    private init() {}

    var appliedConfigDescription: String {
        "isInitialized=\(CoralogixRumManager.shared.sdk.isInitialized)\n" +
        "in-flight=\(inFlight.sorted().joined(separator: ", "))"
    }

    /// Reinitializes the SDK with a tracesExporter that captures `custom-measurement`
    /// spans so the demo can show what the SDK actually emitted (name, duration, labels).
    @discardableResult
    func apply() -> String {
        runToken += 1
        let runToken = self.runToken

        CoralogixRumManager.shared.sdk.shutdown()
        let options = CoralogixExporterOptions(
            coralogixDomain: .EU2,
            userContext: UserContext(userId: "time-measure-demo",
                                     userName: "Time Measure Tester",
                                     userEmail: "time-measure@example.com",
                                     userMetadata: ["test": "timeMeasurement"]),
            environment: "PROD",
            application: "DemoApp-iOS-TimeMeasurement",
            version: "1",
            publicKey: Envs.PUBLIC_KEY.rawValue,
            sessionSampleRate: 100,
            instrumentations: [.mobileVitals: true, .custom: true, .errors: true,
                               .userActions: true, .network: true, .anr: true, .lifeCycle: true],
            collectIPData: true,
            traceParentInHeader: ["enable": true],
            tracesExporter: { [weak self] data in
                let now = Date()
                let rows = data.tracesData.resourceSpans
                    .flatMap { $0.scopeSpans }
                    .flatMap { $0.spans }
                    .compactMap { span -> CapturedTimeMeasurement? in
                        guard span.eventType == CoralogixEventType.customMeasurement.rawValue else { return nil }
                        return CapturedTimeMeasurement(
                            name: Self.stringAttribute(span, "name") ?? "(unknown)",
                            durationMs: Self.doubleAttribute(span, "value"),
                            labels: Self.labelsAttribute(span),
                            receivedAt: now
                        )
                    }
                guard !rows.isEmpty else { return }
                DispatchQueue.main.async {
                    guard let self = self, runToken == self.runToken else { return }
                    self.captured.insert(contentsOf: rows, at: 0)
                }
            },
            debug: true
        )
        CoralogixRumManager.shared.reinitialize(with: options)

        let didApply = CoralogixRumManager.shared.sdk.isInitialized
        isApplied = didApply
        if didApply {
            captured.removeAll()
            inFlight.removeAll()
        }
        return didApply
            ? "SDK reinitialized — sampleRate=100, tracesExporter wired"
            : "❌ SDK failed to initialize"
    }

    // MARK: - Manual API

    @discardableResult
    func start() -> String {
        let key = timerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "name is empty" }
        CoralogixRumManager.shared.sdk.startTimeMeasure(name: key, labels: parseLabels())
        inFlight.insert(key)
        return "Started '\(key)'"
    }

    @discardableResult
    func end() -> String {
        let key = timerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "name is empty" }
        CoralogixRumManager.shared.sdk.endTimeMeasure(name: key)
        inFlight.remove(key)
        return "Ended '\(key)' — span will appear in Captured once the batch flushes"
    }

    // MARK: - Quick presets

    /// Runs `start → async sleep → end` on a background queue so the UI stays responsive.
    /// Each preset uses a unique-enough key so repeated taps don't collide.
    @discardableResult
    func runQuick(label: String, sleepMs: Int) -> String {
        let key = "quick-\(label)"
        let labels: [String: Any] = ["preset": label, "sleepMs": sleepMs]
        CoralogixRumManager.shared.sdk.startTimeMeasure(name: key, labels: labels)
        DispatchQueue.main.async { [weak self] in self?.inFlight.insert(key) }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(sleepMs)) { [weak self] in
            CoralogixRumManager.shared.sdk.endTimeMeasure(name: key)
            DispatchQueue.main.async { self?.inFlight.remove(key) }
        }
        return "Started '\(key)' — will end in \(sleepMs)ms"
    }

    func clearCaptured() {
        // Bumping runToken invalidates any tracesExporter callbacks in flight; their
        // main-queue insert will hit the token guard and drop the row.
        runToken += 1
        captured.removeAll()
    }

    // MARK: - Helpers

    /// Parses the "key=value, key=value" labels TextField into a dict. Returns nil
    /// when empty — `startTimeMeasure(labels:)` accepts nil as "no labels".
    func parseLabels() -> [String: Any]? {
        let trimmed = labelsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var result: [String: Any] = [:]
        for pair in trimmed.split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2, !kv[0].isEmpty else { continue }
            result[kv[0]] = kv[1]
        }
        return result.isEmpty ? nil : result
    }

    private static func stringAttribute(_ span: OtlpSpan, _ key: String) -> String? {
        guard let kv = span.attributes.first(where: { $0.key == key }) else { return nil }
        if case .stringValue(let value) = kv.value { return value }
        return nil
    }

    private static func doubleAttribute(_ span: OtlpSpan, _ key: String) -> Double? {
        // The SDK writes `value` as a Double on the OTel span but the OTLP wire form
        // surfaces every attribute as its `.description` string; round-trip via Double().
        guard let str = stringAttribute(span, key) else { return nil }
        return Double(str)
    }

    private static func labelsAttribute(_ span: OtlpSpan) -> [String: Any]? {
        guard let json = stringAttribute(span, "custom_labels") else { return nil }
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }
}
