//
//  FatalHangRecovery.swift
//  Coralogix
//
//  A hang the process does not survive — the system's watchdog kills it, or the user gives up
//  and swipes it away — is reported by the next launch, as the Android SDK recovers a fatal ANR.
//

import Foundation
import CoralogixInternal

/// What the watchdog leaves on disk while the main thread is hung: enough to report the hang on
/// the next launch if the process never answers again.
struct HangMarker: Codable, Equatable {
    let detectedAt: Date
    /// Tells this process's own crash report apart from an earlier launch's.
    let pid: Int32
    /// The session the hang happened in; nil when there was none yet.
    let session: StoredCrashRecord.Session?
    /// Every thread at detection, main first, in the crash threads' wire shape.
    let threads: String?
    /// The hang's own live event was delivered: the next launch has nothing to add.
    var liveDelivered: Bool

    var crashId: String {
        "anr-\(Int64((detectedAt.timeIntervalSince1970 * 1000).rounded()))-\(pid)"
    }
}

/// Told by the watchdog when a hang it reports starts and when the main thread answers again.
protocol HangObserving: AnyObject {
    func hangDetected(at date: Date, threads: String?)
    func hangEnded()
}

/// Keeps the hang marker while a reported hang lasts, and notes when the hang's own event is
/// delivered, so the next launch reports a hang only the process's end kept from being sent.
final class FatalHangWatch: HangObserving {
    private let store: CrashDeliveryStore
    private let session: () -> StoredCrashRecord.Session?
    private let lock = NSLock()
    private var currentHangId: String?

    init(store: CrashDeliveryStore, session: @escaping () -> StoredCrashRecord.Session?) {
        self.store = store
        self.session = session
    }

    func hangDetected(at date: Date, threads: String?) {
        let marker = HangMarker(detectedAt: date, pid: getpid(), session: session(),
                                threads: threads, liveDelivered: false)
        store.writeHangMarker(marker)
        lock.lock()
        currentHangId = marker.crashId
        lock.unlock()
    }

    func hangEnded() {
        lock.lock()
        currentHangId = nil
        lock.unlock()
        store.clearHangMarker()
    }

    /// Marks the hang under way as reported once `spanId`, its own event, is delivered.
    func awaitDelivery(ofSpan spanId: String, through exporter: CoralogixExporter) {
        lock.lock()
        let hangId = currentHangId
        lock.unlock()
        guard let hangId else { return }
        exporter.awaitLiveDelivery(spanId: spanId) { [store] delivered in
            // Delivered only: an event that was refused or dropped never reached the product.
            if delivered {
                store.markHangDelivered(crashId: hangId)
            }
        }
    }
}

extension CoralogixRum {
    /// A crash this close before the hang's detection can still be the same launch's: a report's
    /// time is kept only to the second.
    static let hangCrashSlack: TimeInterval = 1

    /// Turns the marker a hang left into a stored fatal hang, unless the hang was already reported
    /// by its own event, the launch ended in a crash instead, or there is no record of its session.
    /// The marker is gone afterwards either way. `crashes` are the native crash reports on disk.
    internal func recordFatalHang(reportsHangs: Bool, crashes: [MappedCrash]) {
        let store = self.crashDeliveryStore
        guard let marker = store.hangMarker() else { return }
        defer { store.clearHangMarker() }

        guard reportsHangs else { return }
        if marker.liveDelivered {
            Log.d("[FatalHang] the hang's own event was delivered — not reported again")
            return
        }
        let crashedLater = crashes.contains { crash in
            crash.pid == UInt(marker.pid)
                && (crash.crashTime ?? .distantPast) >= marker.detectedAt.addingTimeInterval(-Self.hangCrashSlack)
        }
        if crashedLater {
            Log.d("[FatalHang] the launch ended in a crash during the hang — the crash is reported instead")
            return
        }
        guard let session = marker.session,
              let snapshots = self.coralogixExporter?.getSessionManager().snapshotStore,
              let counters = Self.counters(of: session, in: snapshots) else {
            Log.d("[FatalHang] no record of the hung session — dropping the hang")
            return
        }
        guard store.storeHang(marker) != nil else { return }
        store.save(StoredCrashRecord(crashId: marker.crashId, kind: .anr, crashTime: marker.detectedAt,
                                     failedUploads: 0, session: session, counters: counters))
    }

    /// The stored fatal hangs to send, newest first, capped like crashes. A file that cannot be
    /// read yet is left; one that is corrupt, or has lost its record, is deleted.
    internal func pendingFatalHangs() -> [CrashDeliveryScheduler.Item] {
        let store = self.crashDeliveryStore
        var hangs: [(copy: URL, marker: HangMarker)] = []
        for file in store.hangs() {
            switch Self.readHang(file) {
            case .readable(let marker):
                guard store.record(for: marker.crashId) != nil else {
                    store.removeCopy(file)
                    continue
                }
                hangs.append((file, marker))
            case .notReadableYet:
                continue
            case .corrupt:
                store.removeCopy(file)
            }
        }
        let sorted = hangs.sorted { $0.marker.detectedAt > $1.marker.detectedAt }
        for dropped in sorted.dropFirst(CrashDeliveryStore.maxPerKind) {
            store.forget(copy: dropped.copy, crashId: dropped.marker.crashId)
        }
        return sorted.prefix(CrashDeliveryStore.maxPerKind).map { .init(crashId: $0.marker.crashId, copy: $0.copy) }
    }

    enum HangReadResult {
        case readable(HangMarker)
        case notReadableYet
        case corrupt
    }

    static func readHang(_ file: URL) -> HangReadResult {
        guard let data = try? Data(contentsOf: file) else { return .notReadableYet }
        guard let marker = try? JSONDecoder().decode(HangMarker.self, from: data) else { return .corrupt }
        return .readable(marker)
    }

    /// Emits a stored fatal hang as a crash in the session it happened in, timed when it was
    /// detected, in a trace of its own.
    internal func emitRecoveredHang(_ marker: HangMarker, as record: StoredCrashRecord) {
        let span = makeSpan(event: .error, source: .console, severity: .error,
                            startTime: marker.detectedAt, startsNewTrace: true)
        self.attribute(span, to: record)
        span.setAttribute(key: Keys.crashEventId.rawValue, value: record.crashId)
        span.setAttribute(key: Keys.isCrash.rawValue, value: true)
        span.setAttribute(key: Keys.errorType.rawValue, value: WireValues.anrErrorType.rawValue)
        span.setAttribute(key: Keys.errorMessage.rawValue, value: WireValues.fatalAnrErrorMessage.rawValue)
        if let threads = marker.threads {
            span.setAttribute(key: Keys.threads.rawValue, value: threads)
        }
        span.end(time: marker.detectedAt)
    }
}
