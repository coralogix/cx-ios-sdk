//
//  CrashInstumentation.swift
//
//
//  Created by Coralogix DEV TEAM on 08/04/2024.
//

import Foundation
import CrashReporter
import CoralogixInternal
#if canImport(CoralogixBootstrap)
// SPM builds the bootstrap as its own module; under CocoaPods it is part of this pod.
import CoralogixBootstrap
#endif

extension CoralogixRum: StoredCrashSending {
    /// Installs crash capture for this launch. Recovering the crashes earlier launches left behind
    /// is a separate step, `recoverPendingCrashes`, which does not depend on this one.
    public func initializeCrashInstrumentation() {
        guard Self.installedCrashReporter() != nil else { return }

        switch FirebaseRuntimeDetector.presence() {
        case .configured:
            // True only when the load-time install holds the process-wide slot. On the fallback
            // path — opt-out, +load failure, or +load never running — the order is not handled,
            // and saying so here is the one place Firebase-first and weak-path meet in the log.
            let orderHandled = CRXCrashBootstrap.reporter != nil
            Log.d(orderHandled
                  ? "host app called FirebaseApp.configure() before your Coralogix SDK init; the crash handler was installed at image load, so the order is handled"
                  : "host app called FirebaseApp.configure() before your Coralogix SDK init; the crash handler was installed at init instead, so Crashlytics can displace it")
        case .linkedButNotConfigured:
            Log.d("Firebase exists, but not configured yet (or you checked too early)")
        case .notLinked:
            Log.d("host app didn't include Firebase at all")
        }
    }

    /// Lines up the crashes earlier launches left behind for `completeCrashRecovery` to send: native
    /// crashes, then fatal hangs, newest first within each kind, as Android sends them.
    ///
    /// Runs at init whatever this launch's sampling roll: the crash belongs to the session that
    /// crashed, so whether it is sent follows that session's decision, not this launch's.
    ///
    /// Reads only the SDK's own copies of the reports (see `CrashDeliveryStore`). A report still in
    /// PLCrashReporter's slot — the load-time copy could not be written, or never ran — is moved
    /// first. Each crash is reported as its delivery record says; a crash read for the first time
    /// gets one, or, when its session left no record to build one from, is dropped.
    ///
    /// Native crashes follow the `.errors` switch and fatal hangs the `.anr` one, both read from
    /// this launch's options.
    internal func recoverPendingCrashes() {
        let options = self.coralogixExporter?.getOptions()
        let reportsCrashes = options.map { Self.shouldRecoverCrashes(options: $0) } ?? false
        let reportsHangs = options?.shouldInitInstrumentation(instrumentation: .anr) ?? false
        let store = self.crashDeliveryStore
        store.deleteLegacyHybridStore()
        if reportsCrashes, let reader = Self.crashReportReader() {
            CRXCrashBootstrap.movePendingReport(of: reader, toDirectory: store.copiesDirectory)
        }

        var readable: [(copy: URL, crash: MappedCrash)] = []
        for copy in store.copies() {
            switch Self.readCopy(copy) {
            case .readable(let crash):
                readable.append((copy, crash))
            case .notReadableYet:
                continue
            case .corrupt:
                store.removeCopy(copy)
            }
        }
        // Read before the native rules below delete anything: a crash during the hang wins.
        self.recordFatalHang(reportsHangs: reportsHangs, crashes: readable.map(\.crash))

        var lined: [CrashDeliveryScheduler.Item] = []
        if reportsCrashes {
            lined += self.lineUpNativeCrashes(readable)
        } else {
            // Copied at image load whatever the options say: not sent, so not kept either.
            for (copy, crash) in readable {
                store.forget(copy: copy, crashId: crash.crashId)
            }
        }
        if reportsHangs {
            lined += self.pendingFatalHangs()
        }

        crashRecoveryLock.lock()
        self.pendingRecoveredCrashes = lined
        crashRecoveryLock.unlock()
    }

    /// The native crashes to send, newest first, capped; each with its delivery record.
    private func lineUpNativeCrashes(_ readable: [(copy: URL, crash: MappedCrash)]) -> [CrashDeliveryScheduler.Item] {
        let store = self.crashDeliveryStore
        let (kept, dropped) = Self.newest(readable, limit: CrashDeliveryStore.maxPerKind)
        for crash in dropped {
            store.forget(copy: crash.copy, crashId: crash.crash.crashId)
        }

        var lined: [CrashDeliveryScheduler.Item] = []
        for (copy, crash) in kept {
            guard store.record(for: crash.crashId) != nil || self.firstRecord(of: crash) != nil else {
                Log.d("[CrashInstrumentation] no record of the crashed session — dropping crash \(crash.crashId)")
                store.removeCopy(copy)
                continue
            }
            lined.append(.init(crashId: crash.crashId, copy: copy))
        }
        return lined
    }

    /// The `limit` newest crashes, newest first, and the rest. A crash with no time sorts oldest.
    static func newest(_ crashes: [(copy: URL, crash: MappedCrash)],
                       limit: Int) -> (kept: [(copy: URL, crash: MappedCrash)], dropped: [(copy: URL, crash: MappedCrash)]) {
        let sorted = crashes.sorted { ($0.crash.crashTime ?? .distantPast) > ($1.crash.crashTime ?? .distantPast) }
        return (Array(sorted.prefix(limit)), Array(sorted.dropFirst(limit)))
    }

    enum CopyReadResult {
        case readable(MappedCrash)
        /// The file exists but cannot be read yet (data protection before the first unlock).
        case notReadableYet
        case corrupt
    }

    static func readCopy(_ copy: URL) -> CopyReadResult {
        guard let data = try? Data(contentsOf: copy) else { return .notReadableYet }
        guard let report = try? PLCrashReport(data: data) else { return .corrupt }
        return .readable(CrashReportMapper.map(PLCrashReportReader(report: report)))
    }

    /// The reporter to keep capturing with.
    ///
    /// Normally this is the instance `CRXCrashBootstrap` enabled at image load — already
    /// capturing, and installed early enough that a crash reporter configured by the host app
    /// (Firebase Crashlytics) reinstates our signal handlers instead of replacing them. See
    /// `CRXCrashBootstrap` for why the install has to happen before `main()`.
    ///
    /// The fallback enables one here, which is what this method did before the bootstrap
    /// existed: a reporter that captures correctly but only from this point on, so a crash
    /// reporter configured earlier can still pre-empt it. Better than no crash reporting at all.
    /// It is reached when the load-time install failed, or when the host app opted out with
    /// `CoralogixDisableEarlyCrashHandler`.
    ///
    /// `candidate` is a parameter so tests can assert the adoption path against a known
    /// instance. They do not drive it to the fallback: that calls `enable()`, which installs
    /// signal handlers process-wide with no way to undo them afterwards.
    internal static func installedCrashReporter(
        candidate: PLCrashReporter? = CRXCrashBootstrap.reporter
    ) -> PLCrashReporter? {
        if let candidate {
            return candidate
        }

        if CRXCrashBootstrap.disabledByHostApp {
            // Warning rather than debug: this is the line support reads to explain why a
            // customer's crashes are being displaced again, and os_log debug is absent from
            // `log show` and from a console capture.
            Log.w("[CrashInstrumentation] early crash-handler install disabled by CoralogixDisableEarlyCrashHandler — enabling at init instead, which a crash reporter configured before this SDK can displace")
        } else if let error = CRXCrashBootstrap.enableError {
            Log.e("[CrashInstrumentation] crash bootstrap could not enable at load: \(error)")
        }

        guard let crashReporter = makeCrashReporter() else { return nil }
        // PLCrashReporter allows one enabled instance per process. If the host app enabled its
        // own before us (App Center Crashes wraps it; some apps use it directly) this fails with
        // PLCrashReporterErrorResourceBusy and ours captures nothing.
        do {
            try crashReporter.enable()
            // Held here so the reporter outlives this call, and so crash context is written only
            // through a reporter this SDK enabled.
            CRXCrashContext.activeReporter = crashReporter
        } catch {
            Log.e("[CrashInstrumentation] PLCrashReporter could not be enabled — another instance already owns the process-wide slot, so crashes from this launch will not be captured: \(error)")
        }
        return crashReporter
    }

    /// The reporter `recoverPendingCrashes` reads the previous launch's report through.
    ///
    /// Reading and purging the pending report does not need the live signal handler, so when the
    /// load-time install is missing this returns an instance that is never enabled. Recovery runs
    /// on launches that do not install crash capture, and must not install it as a side effect.
    private static func crashReportReader() -> PLCrashReporter? {
        CRXCrashBootstrap.reporter ?? makeCrashReporter()
    }

    private static func makeCrashReporter() -> PLCrashReporter? {
        // Local symbolication is strongly recommended for non-release builds only; kept as-is
        // here so the fallback produces the same reports the bootstrap does.
        let config = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: .all)
        guard let crashReporter = PLCrashReporter(configuration: config) else {
            Log.e("Could not create an instance of PLCrashReporter")
            return nil
        }
        return crashReporter
    }

    /// Final step of crash recovery, run right after init completes: hands the crashes
    /// `recoverPendingCrashes` lined up to the delivery scheduler, which sends each one and deletes
    /// its copy and record once that crash is finished with. `completion` runs when that pass ends.
    internal func completeCrashRecovery(completion: (() -> Void)? = nil) {
        crashRecoveryLock.lock()
        let pending = self.pendingRecoveredCrashes
        self.pendingRecoveredCrashes = []
        crashRecoveryLock.unlock()
        self.crashDeliveryScheduler.start(pending, onEnd: completion)
    }

    /// Emits a recovered crash as an error span, under its `crash_event_id`.
    ///
    /// A crash is captured on a later launch, after a fresh session has already been created. The
    /// span is anchored to the crash time, reported under the session it happened in as `record`
    /// describes it, and starts a trace of its own: whatever span is current in this launch had
    /// nothing to do with it.
    internal func emitRecoveredCrash(_ crash: MappedCrash, as record: StoredCrashRecord) {
        let span = makeSpan(event: .error, source: .console, severity: .error,
                            startTime: crash.crashTime, startsNewTrace: true)
        self.attribute(span, to: record)

        span.setAttribute(key: Keys.crashEventId.rawValue, value: crash.crashId)
        span.setAttribute(key: Keys.isCrash.rawValue, value: true)
        span.setAttribute(key: Keys.exceptionType.rawValue, value: crash.exceptionType)
        span.setAttribute(key: Keys.errorType.rawValue, value: crash.errorType)
        span.setAttribute(key: Keys.errorMessage.rawValue, value: crash.errorMessage)
        if let crashTime = crash.crashTime {
            span.setAttribute(key: Keys.crashTimestamp.rawValue, value: "\(crashTime.timeIntervalSince1970.milliseconds)")
        }
        if let processName = crash.processName {
            span.setAttribute(key: Keys.processName.rawValue, value: processName)
        }
        if let applicationIdentifier = crash.applicationIdentifier {
            span.setAttribute(key: Keys.applicationIdentifier.rawValue, value: applicationIdentifier)
        }
        span.setAttribute(key: Keys.pid.rawValue, value: "\(crash.pid)")
        if let triggeredByThread = crash.triggeredByThread {
            span.setAttribute(key: Keys.triggeredByThread.rawValue, value: triggeredByThread)
        }
        span.setAttribute(key: Keys.threads.rawValue, value: crash.threadsJSON)
        if let baseAddress = crash.baseAddress, let arch = crash.arch {
            span.setAttribute(key: Keys.baseAddress.rawValue, value: baseAddress)
            span.setAttribute(key: Keys.arch.rawValue, value: arch)
        }

        span.end(time: crash.crashTime ?? Date())
    }

    /// The delivery record of a crash read for the first time, saved before it is returned: the
    /// crashed session and what its own record held at the crash. nil when there is nothing to
    /// build it from — the session left no record, which is also the case of a crash before the
    /// SDK adopted its first session. Such a crash would otherwise be filed under a session it
    /// did not happen in.
    ///
    /// The session is the one the report's own crash context names. Only a report without one —
    /// written by an SDK version that did not record it — falls back to the session the keychain
    /// says was live when the previous launch ended: for a report that names its session, the
    /// keychain may hold a different one.
    internal func firstRecord(of crash: MappedCrash) -> StoredCrashRecord? {
        guard let sessionManager = self.coralogixExporter?.getSessionManager() else { return nil }
        let session: StoredCrashRecord.Session
        if let named = crash.context?.session {
            session = .init(id: named.id,
                            creationDate: named.creationTimeMillis.map { TimeInterval($0) / 1000 },
                            sampledIn: named.sampledIn)
        } else if let last = sessionManager.lastLaunchSession {
            session = .init(id: last.sessionId, creationDate: last.creationDate, sampledIn: last.sampledIn)
        } else {
            return nil
        }
        guard let counters = Self.counters(of: session, in: sessionManager.snapshotStore) else { return nil }

        let record = StoredCrashRecord(crashId: crash.crashId,
                                       kind: .native,
                                       crashTime: crash.crashTime ?? Date(),
                                       failedUploads: 0,
                                       session: session,
                                       counters: counters)
        self.crashDeliveryStore.save(record)
        return record
    }

    /// The crashed session's counters. A session the SDK had adopted (it has a creation time) but
    /// not recorded yet — a crash right after a rotation — counted nothing; a session that was
    /// never adopted is a crash before init, which has none.
    static func counters(of session: StoredCrashRecord.Session, in store: SessionSnapshotStore) -> SessionSnapshotRecord? {
        if let record = store.record(for: session.id) { return record }
        return session.creationDate == nil ? nil : .empty(sessionId: session.id)
    }

    /// Replaces what `makeSpan` stamped from the relaunch — session, view, counters, app and OS
    /// version — with the crashed session's, as `record` holds them. The counters are reported with
    /// this crash's error added, and neither store is changed: every send reports the same counts.
    ///
    /// An unknown sampling decision is stamped sampled-in: a crash misclassified as sampled-out
    /// would be dropped and purged as resolved.
    internal func attribute(_ span: any Span, to record: StoredCrashRecord) {
        span.setAttribute(key: Keys.sessionId.rawValue, value: record.session.id)
        // The relaunch's previous-session breadcrumbs would override the session set here when
        // the previous launch's pid is the crashed one.
        for key in [Keys.prevPid, .prevSessionId, .prevSessionCreationDate] {
            span.setAttribute(key: key.rawValue, value: nil as AttributeValue?)
        }
        if let creationDate = record.session.creationDate {
            span.setAttribute(key: Keys.sessionCreationDate.rawValue, value: String(Int(creationDate)))
        }
        span.setAttribute(key: Keys.spanSessionSampledIn.rawValue, value: String(record.session.sampledIn ?? true))

        let counters = record.counters
        span.setAttribute(key: Keys.spanViewName.rawValue,
                          value: AttributeValue.string(counters.viewName ?? Keys.undefined.rawValue))
        span.setAttribute(key: Keys.spanViewNumber.rawValue, value: counters.viewNumber.map(AttributeValue.int))
        let versions: [(Keys, String?)] = [(.crashedAppName, counters.appName),
                                           (.crashedAppVersion, counters.appVersion),
                                           (.crashedOsVersion, counters.osVersion),
                                           (.crashedSnapshot, record.reportedCounters.json)]
        for case let (key, value?) in versions {
            span.setAttribute(key: key.rawValue, value: value)
        }
    }

    func sendStoredCrash(_ item: CrashDeliveryScheduler.Item,
                         as record: StoredCrashRecord,
                         completion: @escaping (CrashUploadAnswer) -> Void) {
        guard let exporter = self.coralogixExporter else {
            completion(CrashUploadAnswer(outcome: .notAttempted))
            return
        }
        if record.kind == .anr {
            sendStoredHang(item, as: record, through: exporter, completion: completion)
            return
        }
        switch Self.readCopy(item.copy) {
        case .readable(let crash):
            exporter.awaitCrashUpload(id: crash.crashId, completion)
            self.emitRecoveredCrash(crash, as: record)
            self.flush()
        case .notReadableYet:
            completion(CrashUploadAnswer(outcome: .notAttempted))
        case .corrupt:
            // Can never be sent: finished with, like a report the backend refused.
            completion(CrashUploadAnswer(outcome: .rejected))
        }
    }

    private func sendStoredHang(_ item: CrashDeliveryScheduler.Item,
                                as record: StoredCrashRecord,
                                through exporter: CoralogixExporter,
                                completion: @escaping (CrashUploadAnswer) -> Void) {
        switch Self.readHang(item.copy) {
        case .readable(let marker):
            exporter.awaitCrashUpload(id: record.crashId, completion)
            self.emitRecoveredHang(marker, as: record)
            self.flush()
        case .notReadableYet:
            completion(CrashUploadAnswer(outcome: .notAttempted))
        case .corrupt:
            completion(CrashUploadAnswer(outcome: .rejected))
        }
    }

    func cancelStoredCrashSend() {
        self.coralogixExporter?.spanUploader.cancelStoredCrashUploads()
    }
}

public enum FirebasePresence: Equatable {
    /// FirebaseCore isn't linked into the host app binary.
    case notLinked
    /// FirebaseCore is present, but `FirebaseApp.configure()` hasn't been called yet.
    case linkedButNotConfigured
    /// `FirebaseApp.configure()` was called (default app exists).
    case configured
}

public struct FirebaseRuntimeDetector {

    /// Extra-safe detection: no Firebase dependency, no IMP casting.
    public static func presence() -> FirebasePresence {
        // FIRApp is the Obj-C class exposed by FirebaseCore
        guard let firAppClassAny = NSClassFromString("FIRApp") else {
            return .notLinked
        }

        // Make sure it behaves like an Obj-C NSObject class (so we can safely call `perform`)
        guard let firAppClass = firAppClassAny as? NSObject.Type else {
            // Unlikely, but safest fallback
            return .notLinked
        }

        let defaultAppSel = NSSelectorFromString("defaultApp")
        guard firAppClass.responds(to: defaultAppSel) else {
            // Firebase linked, but API shape not as expected (or very old/new)
            return .linkedButNotConfigured
        }

        // Call +[FIRApp defaultApp] safely (returns nil if not configured)
        let unmanaged = firAppClass.perform(defaultAppSel)
        let obj = unmanaged?.takeUnretainedValue()

        return (obj != nil) ? .configured : .linkedButNotConfigured
    }

    /// Convenience
    public static func isConfigured() -> Bool {
        presence() == .configured
    }
}
