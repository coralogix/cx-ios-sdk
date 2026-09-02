//
//  CrashEventStore.swift
//  Coralogix
//

import Foundation
import CoralogixInternal

/// Durable storage for crash events reported through the hybrid bridge
/// (`reportError(... isCrash: true)`). A crash usually precedes process death,
/// so the event is persisted to disk *before* any upload attempt — a disk write
/// completes reliably inside the handover window, a network round trip does not.
/// Mirrors PLCrashReporter's pending-report model: the stored copy is removed
/// only after an upload is confirmed, otherwise it is re-sent on the next launch.
final class CrashEventStore {
    /// Store-internal identity field, stamped by `append`. Removal is by id so a
    /// confirmed upload deletes only its own event — never an unconfirmed backlog
    /// entry from an earlier launch that happens to share the store.
    static let eventIdKey = "store_event_id"
    /// Store-internal delivery counter, stamped by `append` and incremented by
    /// `claimEventsForResend`. Never reaches the wire: the resend reads named fields
    /// off the stored event rather than forwarding the dictionary wholesale.
    static let attemptCountKey = "store_delivery_attempts"

    private let fileUrl: URL
    private let lock = NSLock()
    /// Crashes are near-singular events; the cap only bounds pathological growth
    /// when uploads keep failing across many launches.
    private let maxStoredEvents = 10

    init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("CoralogixRum", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.fileUrl = folder.appendingPathComponent("pending_crash_events.json")
    }

    /// Persists the event and returns the identity to pass to `remove(ids:)`
    /// once its upload is confirmed.
    @discardableResult
    func append(_ event: [String: Any]) -> String {
        lock.lock()
        defer { lock.unlock() }
        let id = UUID().uuidString
        var stamped = event
        stamped[Self.eventIdKey] = id
        // The caller uploads this event immediately after persisting it: that send is
        // the first of its allowed attempts.
        stamped[Self.attemptCountKey] = CrashDeliveryPolicy.crashTimeAttempt
        var events = readAllLocked()
        events.append(stamped)
        if events.count > maxStoredEvents {
            events.removeFirst(events.count - maxStoredEvents)
        }
        writeLocked(events)
        return id
    }

    func loadAll() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return readAllLocked()
    }

    /// Charges every stored event one delivery attempt and returns those still within
    /// `CrashDeliveryPolicy.maxDeliveryAttempts`, dropping the ones that have run out.
    ///
    /// The charge happens here, on read, before anything is emitted — devices in the
    /// field already carry events that have been re-sent on every launch, and counting
    /// at read time is what lets an upgraded build clear them with no migration step.
    ///
    /// Returns nothing when the new counts could not be persisted. Re-sending against a
    /// count that didn't survive the launch is indistinguishable from having no count at
    /// all, which is the unbounded loop this exists to break.
    func claimEventsForResend() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        let stored = readAllLocked()
        guard !stored.isEmpty else { return [] }

        var claimed = [[String: Any]]()
        for var event in stored {
            // An absent count is a build that predates the counter, whose crash-time send
            // is the one attempt it is known to have spent. A present but unusable count
            // is clamped rather than trusted.
            let spent = (event[Self.attemptCountKey] as? Int)
                .map(CrashDeliveryPolicy.attemptsSpent(fromPersisted:))
                ?? CrashDeliveryPolicy.crashTimeAttempt
            let attempts = spent + 1
            guard attempts <= CrashDeliveryPolicy.maxDeliveryAttempts else {
                Log.w("[CrashEventStore] crash event reached its delivery-attempt cap after \(spent) uploads — dropping it")
                continue
            }
            event[Self.attemptCountKey] = attempts
            claimed.append(event)
        }

        guard !claimed.isEmpty else {
            try? FileManager.default.removeItem(at: fileUrl)
            return []
        }
        guard writeLocked(claimed) else {
            Log.w("[CrashEventStore] could not persist delivery counts — skipping this resend rather than re-sending uncounted")
            return []
        }
        return claimed
    }

    /// Removes only the events with the given identities, keeping any other
    /// entries (e.g. an unconfirmed backlog from a previous launch) intact.
    func remove(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let remaining = readAllLocked().filter { event in
            guard let id = event[Self.eventIdKey] as? String else { return true }
            return !ids.contains(id)
        }
        if remaining.isEmpty {
            try? FileManager.default.removeItem(at: fileUrl)
        } else {
            writeLocked(remaining)
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileUrl)
    }

    private func readAllLocked() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: fileUrl) else {
            return []
        }
        guard let events = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            // A corrupt store is unrecoverable — discard it so it isn't rescanned
            // (and re-fails) on every launch.
            Log.e("[CrashEventStore] pending file is corrupt, discarding")
            try? FileManager.default.removeItem(at: fileUrl)
            return []
        }
        return events
    }

    /// Returns whether the events reached the disk. Callers that re-send what they wrote
    /// must know, so a failed write can drop the event instead of sending it uncounted.
    @discardableResult
    private func writeLocked(_ events: [[String: Any]]) -> Bool {
        guard JSONSerialization.isValidJSONObject(events),
              let data = try? JSONSerialization.data(withJSONObject: events) else {
            Log.e("[CrashEventStore] crash event is not JSON-serializable, skipping persist")
            return false
        }
        do {
            try data.write(to: fileUrl, options: .atomic)
            return true
        } catch {
            Log.e("[CrashEventStore] failed to persist crash events: \(error)")
            return false
        }
    }
}
