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

    func append(_ event: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        var events = readAllLocked()
        events.append(event)
        if events.count > maxStoredEvents {
            events.removeFirst(events.count - maxStoredEvents)
        }
        writeLocked(events)
    }

    func loadAll() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return readAllLocked()
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

    private func writeLocked(_ events: [[String: Any]]) {
        guard JSONSerialization.isValidJSONObject(events),
              let data = try? JSONSerialization.data(withJSONObject: events) else {
            Log.e("[CrashEventStore] crash event is not JSON-serializable, skipping persist")
            return
        }
        do {
            try data.write(to: fileUrl, options: .atomic)
        } catch {
            Log.e("[CrashEventStore] failed to persist crash events: \(error)")
        }
    }
}
