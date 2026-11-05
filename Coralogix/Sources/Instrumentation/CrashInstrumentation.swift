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

extension CoralogixRum {
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

    /// Re-emits the crashes earlier launches left behind.
    ///
    /// Runs at init whatever this launch's sampling roll: the crash belongs to the session that
    /// crashed, so whether it is sent follows that session's decision, not this launch's.
    internal func recoverPendingCrashes() {
        if let crashReporter = Self.crashReportReader(), crashReporter.hasPendingCrashReport() {
            switch self.processPendingCrashReport(using: crashReporter) {
            case .emitted(let reportId):
                // Purge is deferred to completeCrashRecovery(): it must only happen
                // after the upload is confirmed, and the uploader rejects requests
                // until init finishes. Previously the purge was unconditional and ran
                // before the span even left the batch queue, so a short-lived relaunch
                // or an upload failure lost the crash permanently.
                crashRecoveryLock.lock()
                self.pendingCrashPurge = { crashReporter.purgePendingCrashReport() }
                self.pendingCrashReportId = reportId
                crashRecoveryLock.unlock()
            case .unreadable:
                // Nothing recoverable was emitted — drop the corrupt report so it
                // isn't reprocessed (and re-fails) on every launch.
                crashReporter.purgePendingCrashReport()
            }
        }

        // Hybrid crash events persisted by a previous process (see CrashEventStore).
        self.resendPendingStoredCrashEvents()
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

    /// Final step of crash recovery, run right after init completes: force-flushes
    /// the crash spans emitted during `recoverPendingCrashes`, then decides
    /// per-event what to clean up. Each recovered crash is confirmed independently by
    /// its correlation id, so the PLCrashReporter report is purged only if its own
    /// span uploaded, and only the stored events whose own upload succeeded are
    /// removed. Anything unconfirmed stays on disk / on the pending report and is
    /// retried on the next launch (at-least-once delivery).
    internal func completeCrashRecovery() {
        crashRecoveryLock.lock()
        let hasPendingWork = pendingCrashPurge != nil || !pendingRecoveryCrashEventIds.isEmpty
        crashRecoveryLock.unlock()
        guard hasPendingWork else { return }

        self.flush { [weak self] in
            guard let self, let exporter = self.coralogixExporter else { return }

            // Snapshot-and-clear the process-scoped recovery state under the lock;
            // do the confirmation checks and file IO outside it. Cleared state is
            // repopulated from the store / pending report on the next launch, so an
            // unconfirmed item is retried rather than lost.
            self.crashRecoveryLock.lock()
            let purge = self.pendingCrashPurge
            let reportId = self.pendingCrashReportId
            let recoveryIds = self.pendingRecoveryCrashEventIds
            self.pendingCrashPurge = nil
            self.pendingCrashReportId = nil
            self.pendingRecoveryCrashEventIds = []
            self.crashRecoveryLock.unlock()

            // PLCrashReporter report: purge only if its own span uploaded.
            if let reportId, exporter.didConfirmCrashUpload(id: reportId) {
                purge?()
            } else if reportId != nil {
                Log.w("Crash-report upload not confirmed — keeping pending report for next launch")
            }

            // Stored hybrid crashes: remove only the ones whose own upload succeeded.
            let confirmedStoreIds = recoveryIds.filter { exporter.didConfirmCrashUpload(id: $0) }
            self.crashEventStore.remove(ids: confirmedStoreIds)
        }
    }

    enum RecoveryOutcome: Equatable {
        /// The report was emitted as a crash span carrying this `crash_event_id`.
        case emitted(String)
        /// The report could not be loaded or parsed.
        case unreadable
    }

    private func processPendingCrashReport(using crashReporter: PLCrashReporter) -> RecoveryOutcome {
        do {
            let data = try crashReporter.loadPendingCrashReportDataAndReturnError()
            let report = try PLCrashReport(data: data)
            return .emitted(self.emitRecoveredCrash(CrashReportMapper.map(PLCrashReportReader(report: report))))
        } catch let error {
            Log.e("CrashReporter failed to load and parse with error: \(error)")
            return .unreadable
        }
    }

    /// Emits a recovered crash as an error span and returns its `crash_event_id`.
    ///
    /// A crash is captured on the *next* launch, after a fresh session has already been created.
    /// The span is anchored to the crash time (not relaunch time), burnt under the session that
    /// was live when it crashed, and starts a trace of its own: whatever span is current in this
    /// launch had nothing to do with it.
    @discardableResult
    internal func emitRecoveredCrash(_ crash: MappedCrash) -> String {
        let span = makeSpan(event: .error, source: .console, severity: .error,
                            startTime: crash.crashTime, startsNewTrace: true)
        self.overrideSessionForCrashedSession(on: span)
        self.overrideViewForCrashedSession(on: span)

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

        if let crashTime = crash.crashTime {
            span.end(time: crashTime)
        } else {
            span.end()
        }
        return crash.crashId
    }

    /// Replaces the current-session attributes `makeSpan` stamped on the crash span
    /// with the session that was live when the crash happened. No-op when there is
    /// no previous-launch session on record — the span keeps the current session.
    /// Internal: the CrashEventStore resend path (ErrorInstrumentation) applies the
    /// same attribution to recovered hybrid crash events.
    internal func overrideSessionForCrashedSession(on span: any Span) {
        guard let sessionManager = self.coralogixExporter?.getSessionManager() else { return }
        for attr in sessionManager.lastLaunchSessionSpanAttributes() {
            span.setAttribute(key: attr.key, value: attr.value)
        }
    }

    /// Replaces the view `makeSpan` froze onto the crash span — the relaunch process's
    /// live view, which is empty this early in init — with the view that was on-screen
    /// when the crash happened, recovered from the keychain into `ViewManager.prevViewName`.
    /// No-op when the crashed session never showed a view, so the span keeps the empty
    /// frozen view rather than inventing one.
    /// Internal (rather than private) so unit tests can exercise it directly.
    internal func overrideViewForCrashedSession(on span: any Span) {
        guard let prevView = self.coralogixExporter?.getViewManager().getPrevDictionary()[Keys.view.rawValue] as? String,
              !prevView.isEmpty else { return }
        span.setAttribute(key: Keys.spanViewName.rawValue, value: prevView)
    }
    
    func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard junk == 0 else {
            Log.w("sysctl failed with error \(junk)")
            return false
        }
        return (info.kp_proc.p_flag & P_TRACED) != 0
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
