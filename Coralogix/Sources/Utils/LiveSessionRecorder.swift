//
//  LiveSessionRecorder.swift
//  Coralogix
//

import Foundation
import CoralogixInternal

/// Keeps the live session's record current, so a crash at any moment finds the counters, view
/// and versions its session had. Written eagerly — at the first session, on rotation, and on
/// every counter, view or app-context change — rather than only when a snapshot is emitted, and
/// whatever the session's sampling decision.
///
/// Writes run on one serial queue and each reads the live state when it runs, so the last write
/// always reflects the latest state however the triggers interleave. Nothing here runs on the
/// thread that changed the state, which may hold a lock this would need.
final class LiveSessionRecorder {
    private let queue = DispatchQueue(label: Keys.queueSessionRecordQueue.rawValue)
    private let store: SessionSnapshotStore

    init(store: SessionSnapshotStore) {
        self.store = store
    }

    /// Persists what `liveRecord` returns when the write runs; nil writes nothing.
    func record(_ liveRecord: @escaping () -> SessionSnapshotRecord?) {
        queue.async { [store] in
            guard let record = liveRecord() else { return }
            store.persist(record)
        }
    }

    /// Waits for the writes scheduled so far. Tests only.
    func waitForPendingWrites() {
        queue.sync {}
    }
}
