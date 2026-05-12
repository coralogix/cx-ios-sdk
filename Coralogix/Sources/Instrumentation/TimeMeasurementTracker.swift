//
//  TimeMeasurementTracker.swift
//
//  In-memory tracker for the custom time measurement API (CX-28920).
//  Holds in-flight `start` → `end` pairs keyed by trimmed name, computes the
//  elapsed duration on `end`, and discards everything when the session goes idle.
//  Lock-protected; callers emit the resulting span *after* releasing the lock.
//
//  Reference: Browser SDK `timeMeasurementTracker.ts` (web parity).
//  Full design: tech-debt/CX-28920_custom_time_measurement_api.md §3.1
//

import Foundation
import CoralogixInternal

final class TimeMeasurementTracker {
    private struct Entry {
        // DispatchTime.now().uptimeNanoseconds — monotonic, immune to wall-clock changes
        // (NTP step, user toggling time). Date() can jump and produce negative durations.
        let startedAt: UInt64
        let labels: [String: Any]?
    }

    private let lock = NSLock()
    private var measurements: [String: Entry] = [:]
    private weak var sessionManager: SessionManager?

    init(sessionManager: SessionManager?) {
        self.sessionManager = sessionManager
    }

    func startMeasurement(key: String, labels: [String: Any]?) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Log.d("[TimeMeasurement] start ignored — empty key")
            return
        }

        // Read isIdle outside the lock (best-effort, no I/O). The idle-clear and
        // the insert below happen under the same lock so they're atomic w.r.t.
        // each other — Browser parity with web SDK `timeMeasurementTracker.ts:34-38`.
        let isIdle = sessionManager?.isIdle == true

        lock.lock()
        defer { lock.unlock() }

        if isIdle, !measurements.isEmpty {
            Log.d("[TimeMeasurement] session idle — discarding \(measurements.count) in-flight measurements")
            measurements.removeAll(keepingCapacity: false)
        }

        if measurements[trimmed] != nil {
            Log.d("[TimeMeasurement] start ignored — duplicate key '\(trimmed)'")
            return
        }
        measurements[trimmed] = Entry(
            startedAt: DispatchTime.now().uptimeNanoseconds,
            labels: labels
        )
    }

    /// Returns nil when the key was never started, when the key is empty, or when the
    /// session has gone idle and timers were wiped.
    func endMeasurement(key: String) -> (durationMs: Double, labels: [String: Any]?)? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let isIdle = sessionManager?.isIdle == true

        // Critical section: maybe clear, then remove the entry. Release the lock
        // before doing the duration math, logging, or returning the tuple.
        lock.lock()
        if isIdle, !measurements.isEmpty {
            Log.d("[TimeMeasurement] session idle — discarding \(measurements.count) in-flight measurements")
            measurements.removeAll(keepingCapacity: false)
        }
        let entry = measurements.removeValue(forKey: trimmed)
        lock.unlock()

        guard let entry = entry else {
            Log.d("[TimeMeasurement] end ignored — no in-flight measurement '\(trimmed)'")
            return nil
        }

        // `&-` wraps on underflow instead of trapping. uptimeNanoseconds is
        // monotonic so this shouldn't happen in practice, but an SDK must never
        // crash the host app (CLAUDE.md rule) — wrap defensively.
        let elapsedNs = DispatchTime.now().uptimeNanoseconds &- entry.startedAt
        return (Double(elapsedNs) / 1_000_000.0, entry.labels)
    }

    /// Called from `CoralogixRum.shutdown()` and tests. Drops all in-flight state.
    func teardown() {
        lock.lock()
        defer { lock.unlock() }
        measurements.removeAll(keepingCapacity: false)
    }
}
