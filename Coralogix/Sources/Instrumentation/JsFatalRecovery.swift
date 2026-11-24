//
//  JsFatalRecovery.swift
//  Coralogix
//
//  A React Native JS fatal ends the process in a native crash of its own: RN raises
//  `RCTFatalException` (the bridge) or terminates on `facebook::jsi::JSError` (bridgeless), and
//  PLCrashReporter records it. The fatal handler's error is sent at once, as on Android, and kept
//  on disk with the process it came from. The next launch, the first that can read the native
//  report, drops the report that process left naming that error, and sends the JS error again
//  only if it was never delivered.
//

import Foundation

/// A process as PLCrashReporter names it in its report: the pid, and the whole second the kernel
/// started it. PLCrashReporter writes `p_starttime.tv_sec`, so the two compare exactly.
struct ProcessIdentity: Codable, Equatable {
    let pid: Int32
    let startSecond: Int64

    /// nil when the kernel would not say.
    static let current: ProcessIdentity? = ColdDetector.processStartTimeval().map {
        ProcessIdentity(pid: getpid(), startSecond: Int64($0.tv_sec))
    }

    /// Whether `crash` is this process's own report.
    func wrote(_ crash: MappedCrash) -> Bool {
        // A pid read back from disk is never trusted to convert: a negative one matches nothing.
        guard let ownPid = UInt(exactly: pid), crash.pid == ownPid,
              let start = crash.processStartTime.flatMap({ Int64(exactly: $0.timeIntervalSince1970) }) else { return false }
        return start == startSecond
    }
}

/// React Native's fatal-handler error, sent live and kept for the next launch: to drop its
/// process's native report, and to send it again if the live send was never delivered.
struct HeldJsFatal: Codable, Equatable {
    static let crashIdPrefix = "jsfatal-"

    let crashId: String
    let process: ProcessIdentity
    let crashTime: Date
    let session: StoredCrashRecord.Session
    let fields: ErrorFields
    /// Set once the live send is delivered.
    var liveDelivered: Bool? = nil

    static func isHeld(crashId: String) -> Bool {
        crashId.hasPrefix(crashIdPrefix)
    }

    /// Whether `crash` is the native report React Native ended the process with for this error, as
    /// Android tells its `JavascriptException` apart. React Native describes it as `<message>` or
    /// `<name>: <message>`, followed by a comma or a line break (its JS engine, component stack or
    /// JS stack), or cut short: at 175 characters ending in "...", or — bridgeless only — by the
    /// bytes a C++ exception's message is kept to. A native `RCTFatal`, or another JS fatal of this
    /// process, does not name it, and is sent as well: two events, never none. Neither does any
    /// report for a fatal with no message, which would tell nothing apart, nor one whose cut split
    /// a character, which leaves React Native's report without its message.
    func isNamed(by crash: MappedCrash) -> Bool {
        guard !fields.message.isEmpty, let described = crash.jsFatalDescription else { return false }
        let named = fields.errorType.flatMap { $0.isEmpty ? nil : "\($0): \(fields.message)" }
        // The bridge's reason always goes on after the description, so only a C++ exception's
        // message, kept to a number of bytes, can end inside it.
        let mayEndCut = crash.kind == .cxx
        return [fields.message, named].compactMap { $0 }.contains {
            Self.head($0, startsDescription: described, mayEndCut: mayEndCut)
        }
    }

    /// The shortest part of the head a description cut short must carry; a cut leaves far more.
    static let minimumCutHead = 32

    static func head(_ head: String, startsDescription described: String, mayEndCut: Bool) -> Bool {
        let head = Array(head.unicodeScalars)
        let described = Array(described.unicodeScalars)
        let shared = zip(head, described).prefix { $0 == $1 }.count
        let rest = described[shared...]
        let cut = Array("...".unicodeScalars)
        if shared == head.count {
            guard let next = rest.first else { return true }
            return next == "," || next == "\n" || rest.starts(with: cut)
        }
        return shared >= minimumCutHead && ((mayEndCut && rest.isEmpty) || rest.starts(with: cut))
    }
}

extension CoralogixRum {
    /// The mangled C++ type RN's bridgeless TurboModule layer terminates with when the fatal
    /// handler raises `RCTFatalException` (`convertNSExceptionToJSError`).
    static let jsErrorCxxType = "N8facebook3jsi7JSErrorE"

    /// The live session as a crash record names it; nil before the SDK has one.
    var liveCrashSession: StoredCrashRecord.Session? {
        sessionManager?.lastPublishedCrashStamp.map {
            StoredCrashRecord.Session(id: $0.sessionId, creationDate: $0.creationDate, sampledIn: $0.sampledIn)
        }
    }

    /// Sends React Native's fatal now, as a crash, and keeps it for the next
    /// launch. Returns false, leaving it to the usual live path and its native report to be sent
    /// as well, when this process or its session is unknown or the file cannot be written.
    ///
    /// Only a delivery the server answered marks it delivered. One the process ends before the
    /// answer arrives is sent again by the next launch, as Android sends a crash whose live upload
    /// got no answer: the same error twice, never none.
    func reportReactNativeFatal(_ fields: ErrorFields) -> Bool {
        guard let process = ownProcess, let session = liveCrashSession else { return false }
        let held = HeldJsFatal(crashId: HeldJsFatal.crashIdPrefix + UUID().uuidString,
                               process: process, crashTime: Date(), session: session, fields: fields)
        let store = crashDeliveryStore
        guard store.storeJsFatal(held) else { return false }
        let span = makeSpan(event: .error, source: .crash, severity: .error)
        // Before the span ends, so the answer cannot come ahead of its listener.
        coralogixExporter?.awaitLiveDelivery(spanId: span.context.spanId.hexString) { delivered in
            // Delivered only: one refused or dropped never reached the product.
            if delivered { store.markJsFatalDelivered(crashId: held.crashId) }
        }
        fields.apply(to: span)
        span.end()
        return true
    }

    /// Takes the native report naming each kept React Native fatal that its process left out of
    /// `readable` (`HeldJsFatal.isNamed(by:)`), and lines up the fatals whose live send was never
    /// delivered, to send again.
    ///
    /// A fatal is settled — its native report forgotten, and it either deleted, delivered, or given
    /// a delivery record — on the first launch that reads it. A report already being sent from an
    /// earlier launch wins instead; a report that turns up only on a later launch, while an
    /// undelivered fatal still waits, is forgotten then. Every doubt keeps the native report: two
    /// events, never none. Like native crashes, kept fatals follow this launch's `.errors` switch.
    ///
    /// A fatal whose native report was not found while one may still be on its way
    /// (`nativeMayBePending`: a copy not readable yet, or a report left in PLCrashReporter's slot)
    /// is kept for a later launch, so that report is still dropped when it is read.
    ///
    /// Returns the fatals to send, newest first and capped, and whether any was left for a later
    /// launch, which still needs its launch's session snapshot.
    internal func settleJsFatals(_ readable: inout [(copy: URL, crash: MappedCrash)],
                                 reportsCrashes: Bool,
                                 nativeMayBePending: Bool) -> (lined: [CrashDeliveryScheduler.Item], unsettled: Bool) {
        let store = self.crashDeliveryStore
        var held: [(file: URL, fatal: HeldJsFatal)] = []
        var unsettled = false
        for file in store.jsFatals() {
            switch Self.readJsFatal(file) {
            case .readable(let fatal):
                // Still running: a fatal the handler survived (a debug build, a custom fatal
                // handler) is the next launch's to send.
                if fatal.process != ownProcess { held.append((file, fatal)) }
            case .notReadableYet:
                unsettled = true
            case .corrupt:
                store.removeCopy(file)
            }
        }
        guard reportsCrashes else {
            for (file, fatal) in held { store.forget(copy: file, crashId: fatal.crashId) }
            return ([], unsettled)
        }

        // Capped before anything is settled: a fatal over the cap leaves its native report alone.
        let newest = held.sorted { $0.fatal.crashTime > $1.fatal.crashTime }
        for (file, fatal) in newest.dropFirst(CrashDeliveryStore.maxPerKind) {
            store.forget(copy: file, crashId: fatal.crashId)
        }
        var lined: [CrashDeliveryScheduler.Item] = []
        for (file, fatal) in newest.prefix(CrashDeliveryStore.maxPerKind) {
            let nativeIndex = readable.firstIndex { fatal.process.wrote($0.crash) && fatal.isNamed(by: $0.crash) }
            if nativeIndex == nil, nativeMayBePending {
                unsettled = true
                continue
            }
            let nativeIsRecorded = nativeIndex.map { store.record(for: readable[$0].crash.crashId) != nil } ?? false
            // Already reported by its live send: only its native report is left to drop.
            if fatal.liveDelivered == true {
                if let nativeIndex, !nativeIsRecorded {
                    let native = readable.remove(at: nativeIndex)
                    Log.d("[JsFatalRecovery] \(fatal.crashId) was delivered live — dropping its native report \(native.crash.crashId)")
                    store.forget(copy: native.copy, crashId: native.crash.crashId)
                }
                store.removeCopy(file)
                continue
            }
            let sendsFatal: Bool
            switch store.lookUpRecord(for: fatal.crashId) {
            case .found:
                sendsFatal = true
            case .unreadable:
                // Neither can be recorded yet: both wait for a later launch.
                unsettled = true
                if let nativeIndex { readable.remove(at: nativeIndex) }
                continue
            case .missing where nativeIsRecorded:
                Log.d("[JsFatalRecovery] the native report of \(fatal.crashId) is already being sent — dropping the held fatal")
                sendsFatal = false
            case .missing:
                sendsFatal = self.recordHeldFatal(fatal)
            }
            guard sendsFatal else {
                store.removeCopy(file)
                continue
            }
            if let nativeIndex, !nativeIsRecorded {
                let native = readable.remove(at: nativeIndex)
                Log.d("[JsFatalRecovery] \(fatal.crashId) is sent in place of its native report \(native.crash.crashId)")
                store.forget(copy: native.copy, crashId: native.crash.crashId)
            }
            lined.append(.init(crashId: fatal.crashId, copy: file))
        }
        return (lined, unsettled)
    }

    /// Saves the delivery record of a held fatal read for the first time. False when there is no
    /// record of its session to attribute it with, or the record did not reach disk.
    private func recordHeldFatal(_ fatal: HeldJsFatal) -> Bool {
        guard let snapshots = self.coralogixExporter?.getSessionManager().snapshotStore,
              let counters = Self.counters(of: fatal.session, in: snapshots) else {
            Log.d("[JsFatalRecovery] no record of the crashed session — dropping \(fatal.crashId), its native report is sent")
            return false
        }
        return crashDeliveryStore.save(StoredCrashRecord(crashId: fatal.crashId, kind: .native, crashTime: fatal.crashTime,
                                                         failedUploads: 0, session: fatal.session, counters: counters))
    }

    enum JsFatalReadResult {
        case readable(HeldJsFatal)
        case notReadableYet
        case corrupt
    }

    static func readJsFatal(_ file: URL) -> JsFatalReadResult {
        guard let data = try? Data(contentsOf: file) else { return .notReadableYet }
        guard let fatal = try? JSONDecoder().decode(HeldJsFatal.self, from: data) else { return .corrupt }
        return .readable(fatal)
    }

    func sendStoredJsFatal(_ item: CrashDeliveryScheduler.Item,
                           as record: StoredCrashRecord,
                           through exporter: CoralogixExporter,
                           completion: @escaping (CrashUploadAnswer) -> Void) {
        switch Self.readJsFatal(item.copy) {
        case .readable(let fatal):
            exporter.awaitCrashUpload(id: record.crashId, completion)
            self.emitRecoveredJsFatal(fatal, as: record)
            self.flushSpans()
        case .notReadableYet:
            completion(CrashUploadAnswer(outcome: .notAttempted))
        case .corrupt:
            completion(CrashUploadAnswer(outcome: .rejected))
        }
    }

    /// Emits a held fatal as the error it would have been live, in the session it happened in,
    /// timed when it was reported, in a trace of its own.
    internal func emitRecoveredJsFatal(_ fatal: HeldJsFatal, as record: StoredCrashRecord) {
        let span = makeSpan(event: .error, source: .crash, severity: .error,
                            startTime: fatal.crashTime, startsNewTrace: true)
        self.attribute(span, to: record)
        span.setAttribute(key: Keys.crashEventId.rawValue, value: record.crashId)
        fatal.fields.apply(to: span)
        span.end(time: fatal.crashTime)
    }
}
