//
//  CrashReportAttemptCounter.swift
//  Coralogix
//

import Foundation
import CoralogixInternal

/// How many times a single crash report may be uploaded before the SDK gives up on it.
///
/// A crash report is kept on disk until its upload is confirmed, and confirmation is a
/// force flush bounded by `Global.BatchSpan.forceFlushTimeout`. A cold launch on poor
/// connectivity misses that window, so without a ceiling the same report is re-emitted
/// on every launch for the life of the install.
enum CrashDeliveryPolicy {
    /// Uploads allowed per report, counting the one made when the crash was reported.
    static let maxDeliveryAttempts = 3

    /// The upload made at crash time, before the process died. A stored hybrid event
    /// that carries no count was written by a build that had no counter, and its
    /// crash-time send is the attempt it has already spent. The PLCrashReporter report
    /// has no equivalent — it is only ever sent on a later launch — so an absent
    /// sidecar there means nothing has been sent yet.
    static let crashTimeAttempt = 1

    /// Reads a count off disk into the range the cap logic can reason about.
    ///
    /// These files are ours, so a negative count or one past the cap means the file was
    /// truncated or edited. Such a count is treated as fully spent rather than allowed to
    /// grant extra retries — a negative value would otherwise take many launches to reach
    /// the cap, silently restoring the unbounded re-sending this cap exists to stop. It
    /// also keeps the caller's `+ 1` away from an overflow trap, which would crash the
    /// host app during startup.
    static func attemptsSpent(fromPersisted count: Int) -> Int {
        return (0...maxDeliveryAttempts).contains(count) ? count : maxDeliveryAttempts
    }
}

/// Delivery-attempt count for the pending PLCrashReporter report, which carries no
/// metadata of its own to hold one. Keyed to the report's identity so a genuinely new
/// crash starts from zero rather than inheriting the count of the one it replaced.
///
/// Only one record is kept: PLCrashReporter holds at most one pending report.
final class CrashReportAttemptCounter {
    private static let identityKey = "report_identity"
    private static let attemptsKey = "delivery_attempts"

    private let fileUrl: URL
    private let lock = NSLock()

    init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("CoralogixRum", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.fileUrl = folder.appendingPathComponent("crash_report_attempts.json")
    }

    /// Records an upload attempt for the report identified by `identity` and reports
    /// whether that report may still be sent.
    ///
    /// Returns `false` once the cap is reached, and also when the new count could not be
    /// persisted: an attempt that leaves no durable trace would be made again on the next
    /// launch, and on every launch after it, which is the loop this counter exists to break.
    func registerAttempt(identity: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let attempts = attemptsLocked(matching: identity) + 1
        guard attempts <= CrashDeliveryPolicy.maxDeliveryAttempts else { return false }
        return writeLocked(identity: identity, attempts: attempts)
    }

    /// Discards the record. Called when the report it counts leaves the disk — delivered,
    /// corrupt, or capped — so nothing later inherits its count.
    func forget() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileUrl)
    }

    /// Attempts already recorded for `identity`, or zero when the record belongs to a
    /// different crash, is missing, or is unreadable. A corrupt record is treated as a
    /// fresh start; the next write replaces it, so the cap still applies from there on.
    private func attemptsLocked(matching identity: String) -> Int {
        guard let data = try? Data(contentsOf: fileUrl),
              let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              record[Self.identityKey] as? String == identity,
              let attempts = record[Self.attemptsKey] as? Int else {
            return 0
        }
        return CrashDeliveryPolicy.attemptsSpent(fromPersisted: attempts)
    }

    private func writeLocked(identity: String, attempts: Int) -> Bool {
        let record: [String: Any] = [Self.identityKey: identity, Self.attemptsKey: attempts]
        guard let data = try? JSONSerialization.data(withJSONObject: record) else {
            Log.e("[CrashReportAttemptCounter] attempt record is not JSON-serializable")
            return false
        }
        do {
            try data.write(to: fileUrl, options: .atomic)
            return true
        } catch {
            Log.e("[CrashReportAttemptCounter] failed to persist attempt count: \(error)")
            return false
        }
    }
}
