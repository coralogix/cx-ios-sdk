//
//  CrashInstumentation.swift
//
//
//  Created by Coralogix DEV TEAM on 08/04/2024.
//

import Foundation
import CrashReporter
import CoralogixInternal

/// The subset of `PLCrashReporter` the pending-report recovery flow depends on.
/// A protocol (rather than the concrete type) so tests can drive recovery with a
/// canned report and observe whether the report is purged.
protocol CrashReporting: AnyObject {
    func hasPendingCrashReport() -> Bool
    func loadPendingCrashReportDataAndReturnError() throws -> Data
    @discardableResult func purgePendingCrashReport() -> Bool
}

extension PLCrashReporter: CrashReporting {}

extension CoralogixRum {
    #if DEBUG
    /// Test seam: when set, supplies the crash reporter used for pending-report
    /// recovery instead of creating a real `PLCrashReporter`. Static because crash
    /// instrumentation, like all instrumentation here, is installed once during
    /// init — there is no instance to reach beforehand. `#if DEBUG` so it never
    /// ships in a release binary, matching `CoralogixExporter.testExportCallback`.
    static var crashReporterProvider: (() -> CrashReporting?)?
    #endif

    public func initializeCrashInstrumentation() {
        guard let crashReporter = Self.makePendingCrashReporter() else { return }

        // Try loading the crash report.
        if crashReporter.hasPendingCrashReport() {
            // Correlation id tying the emitted crash span to its upload confirmation,
            // so the purge is gated on THIS report's own delivery.
            let reportId = UUID().uuidString
            if self.processPendingCrashReport(using: crashReporter, crashEventId: reportId) {
                // Purge is deferred to completeCrashRecovery(): it must only happen
                // after the upload is confirmed, and the uploader rejects requests
                // until init finishes. Previously the purge was unconditional and ran
                // before the span even left the batch queue, so a short-lived relaunch
                // or an upload failure lost the crash permanently.
                crashRecoveryLock.lock()
                self.pendingCrashPurge = { crashReporter.purgePendingCrashReport() }
                self.pendingCrashReportId = reportId
                crashRecoveryLock.unlock()
            } else {
                // Nothing recoverable was emitted — drop the corrupt report so it
                // isn't reprocessed (and re-fails) on every launch.
                crashReporter.purgePendingCrashReport()
            }
        }

        // Hybrid crash events persisted by a previous process (see CrashEventStore).
        self.resendPendingStoredCrashEvents()
    }

    /// Returns the crash reporter used for recovery: the injected test reporter when
    /// one is set, otherwise a real, enabled `PLCrashReporter`.
    private static func makePendingCrashReporter() -> CrashReporting? {
        #if DEBUG
        if let provider = crashReporterProvider {
            return provider()
        }
        #endif

        // It is strongly recommended that local symbolication only be enabled for non-release builds.
        // Use [] for release versions.
        let config = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: .all)
        guard let crashReporter = PLCrashReporter(configuration: config) else {
            Log.e("Could not create an instance of PLCrashReporter")
            return nil
        }

        switch FirebaseRuntimeDetector.presence() {
        case .configured:
            Log.d("host app called FirebaseApp.configure() before your Coralogix SDK init, some crash reports may be dropped")
        case .linkedButNotConfigured:
            Log.d("Firebase exists, but not configured yet (or you checked too early)")
        case .notLinked:
            Log.d("host app didn't include Firebase at all")
        }

        crashReporter.enable()
        return crashReporter
    }

    /// Final step of crash recovery, run right after init completes: force-flushes
    /// the crash spans emitted during `initializeCrashInstrumentation`, then decides
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

    /// Returns `true` when the report was parsed and emitted as a crash span,
    /// `false` when the report could not be loaded or parsed. `crashEventId`
    /// correlates the emitted span with its upload confirmation.
    private func processPendingCrashReport(using crashReporter: CrashReporting, crashEventId: String) -> Bool {
        do {
            let data = try crashReporter.loadPendingCrashReportDataAndReturnError()
            return self.emitCrashSpan(fromReportData: data, crashEventId: crashEventId)
        } catch let error {
            Log.e("CrashReporter failed to load report with error: \(error)")
            return false
        }
    }

    /// Parses raw `PLCrashReport` data into a crash span and emits it, returning
    /// `true` on success and `false` when the data cannot be parsed. Split out of
    /// `processPendingCrashReport` (rather than private) so tests can drive the
    /// parse/emit path with a canned report without a live `PLCrashReporter`.
    internal func emitCrashSpan(fromReportData data: Data, crashEventId: String) -> Bool {
        do {
            // Retrieving crash reporter data.
            let report = try PLCrashReport(data: data)

            // A crash is captured on the *next* launch, after a fresh session has
            // already been created. Anchor the span to the crash time (not relaunch
            // time) and burn it under the session that was live when it crashed —
            // recovered from the keychain into SessionManager at init.
            let crashTimestamp = report.systemInfo.timestamp
            let span = makeSpan(event: .error, source: .console, severity: .error, startTime: crashTimestamp)
            self.overrideSessionForCrashedSession(on: span)
            self.overrideViewForCrashedSession(on: span)

            // Raw crash marker read back by the exporter to confirm this report's
            // upload (crashEventIds/didConfirmCrashUpload) — the encoded is_crash
            // derived from `threads` at build time is off the wire and not visible
            // there, so without this the pending report is never purged and the
            // crash re-sends on every launch.
            span.setAttribute(key: Keys.isCrash.rawValue, value: true)
            span.setAttribute(key: Keys.crashEventId.rawValue, value: crashEventId)
            span.setAttribute(key: Keys.exceptionType.rawValue, value: report.signalInfo.name)
            if let crashTimestamp {
                span.setAttribute(key: Keys.crashTimestamp.rawValue, value: "\(crashTimestamp.timeIntervalSince1970.milliseconds)")
            }
            span.setAttribute(key: Keys.processName.rawValue, value: report.processInfo.processName)
            span.setAttribute(key: Keys.applicationIdentifier.rawValue, value: report.applicationInfo.applicationIdentifier)
            span.setAttribute(key: Keys.pid.rawValue, value: "\(report.processInfo.processID)")
            
            self.createStackTrace(report: report, span: span)
            
            if let text = PLCrashReportTextFormatter.stringValue(for: report, with: PLCrashReportTextFormatiOS) {
                let substrings = text.components(separatedBy: "\n")
                for value in substrings {
                    if let processName = report.processInfo.processName,
                       value.contains("+\(processName)") {
                        let details = extractMemoryAddressAndArchitecture(input: value)
                        if details.count == 7 {
                            let baseAddress = details[0]  // Extracting the base memory address
                            span.setAttribute(key: Keys.baseAddress.rawValue, value: "\(baseAddress)")
                            let arch = details[4]     // Extracting the architecture
                            span.setAttribute(key: Keys.arch.rawValue, value: "\(arch)")
                        }
                    }
                }
            } else {
                Log.e("CrashReporter: can't convert report to text")
            }
            if let crashTimestamp {
                span.end(time: crashTimestamp)
            } else {
                span.end()
            }
            return true
        } catch let error {
            Log.e("CrashReporter failed to parse report with error: \(error)")
            return false
        }
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
    
    private func createStackTrace(report: PLCrashReport, span: any Span) {
        var threads = [String]()
        for case let thread as PLCrashReportThreadInfo in report.threads {
            if thread.crashed {
                span.setAttribute(key: Keys.triggeredByThread.rawValue, value: thread.threadNumber)
            }
            
            let crashedThreadFrames = crashedThread(report: report, thread: thread)
            let data = self.parseFrameArray(crashedThreadFrameArray: crashedThreadFrames)
            threads.append(Helper.convertArrayToJsonString(array: data))
        }
        span.setAttribute(key: Keys.threads.rawValue, value: Helper.convertArrayOfStringToJsonString(array: threads))
    }
    
    func parseFrameArray(crashedThreadFrameArray: [StackFrame]) -> [[String: Any]] {
        var result = [[String: Any]]()
        for frame in crashedThreadFrameArray {
            var frameObj = [String: Any]()
            frameObj[Keys.frameNumber.rawValue] = frame.frameNumber
            frameObj[Keys.binary.rawValue] = frame.binary
            frameObj[Keys.functionAddressCalled.rawValue] = frame.functionAdresseCalled
            frameObj[Keys.base.rawValue] = frame.base
            frameObj[Keys.offset.rawValue] = frame.offset
            result.append(frameObj)
        }
        return result
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
    
    struct StackFrame {
        let frameNumber: String
        let binary: String
        let functionAdresseCalled: String
        let base: String
        let offset: String
        let description: String
    }
    
    private func crashedThread(report: PLCrashReport, thread: PLCrashReportThreadInfo) -> [StackFrame] {
        var stackFrames = [StackFrame]()
        // stack.append("Thread \(thread.threadNumber) Crashed:")
        var frameNum = 0
        while frameNum < thread.stackFrames.count {
            if let frame = thread.stackFrames[frameNum] as? PLCrashReportStackFrameInfo {
                let stackFrame = formatStackFrame(frame: frame, frameNum: frameNum, report: report)
                stackFrames.append(stackFrame)
            }
            frameNum += 1
        }
        return stackFrames
    }
    
    private func formatStackFrame(frame: PLCrashReportStackFrameInfo, frameNum: Int, report: PLCrashReport) -> StackFrame {
        var baseAddress: UInt64 = 0
        var pcOffset: UInt64 = 0
        var imageName = "???"
        var symbolString = ""
        
        if let imageInfo = report.image(forAddress: frame.instructionPointer) {
            imageName = imageInfo.imageName
            imageName = URL(fileURLWithPath: imageName).lastPathComponent
            baseAddress = imageInfo.imageBaseAddress
            pcOffset = frame.instructionPointer - imageInfo.imageBaseAddress
        }
        
        var offset: String = ""
        var base: String = ""
        if let symbolInfo = frame.symbolInfo,
           let symbolName = symbolInfo.symbolName {
            let symOffset = frame.instructionPointer - frame.symbolInfo.startAddress
            offset = String(format: "%ld", symOffset)
            base = symbolName
            symbolString = String(format: "%@ + %ld", symbolName, symOffset)
        } else {
            offset = String(format: "%ld", pcOffset)
            base = String(format: "0x%lx", baseAddress)
            symbolString = String(format: "0x%lx + %ld", baseAddress, pcOffset)
        }
        let description = String(format: "%-4ld%-35@ 0x%016lx %@", frameNum, imageName, frame.instructionPointer, symbolString)
        let stackFrame = StackFrame(frameNumber: "\(frameNum)",
                                    binary: imageName,
                                    functionAdresseCalled: String(format: "0x%016lx", frame.instructionPointer),
                                    base: base,
                                    offset: offset,
                                    description: description)
        
        return stackFrame
    }
    
    private func extractMemoryAddressAndArchitecture(input: String) -> [String] {
        let pattern = #"[^\s]+"#
        let matches = input.matches(for: pattern)
        return matches
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
