//
//  ErrorInstrumentation.swift
//  
//
//  Created by Coralogix DEV TEAM on 07/04/2024.
//

import Foundation
import CoralogixInternal

extension CoralogixRum {
    // MARK: - Feature flags
    private var isErrorsEnabled: Bool {
        self.options?.shouldInitInstrumentation(instrumentation: .errors) ?? false
    }
    
    private var isCustomOrLifecycleEnabled: Bool {
        let opts = self.options
        return (opts?.shouldInitInstrumentation(instrumentation: .custom) ?? false)
        || (opts?.shouldInitInstrumentation(instrumentation: .lifeCycle) ?? false)
    }
    
    func reportErrorWith(exception: NSException,
                         data: [String: Any]? = nil,
                         labels: [String: Any]? = nil) {
        guard isErrorsEnabled else { return }
        let userInfo = Helper.convertDictionary(exception.userInfo ?? [:])
        self.writeError(
            domain: exception.name.rawValue,
            code: 0,
            message: exception.reason ?? "",
            userInfo: userInfo,
            customAttributes: data,
            labels: labels
        )
    }

    func reportErrorWith(error: NSError,
                         data: [String: Any]? = nil,
                         labels: [String: Any]? = nil) {
        guard isErrorsEnabled else { return }
        self.writeError(
            domain: error.domain,
            code: error.code,
            message: error.localizedDescription,
            userInfo: error.userInfo,
            customAttributes: data,
            labels: labels
        )
    }

    func reportErrorWith(error: Error,
                         data: [String: Any]? = nil,
                         labels: [String: Any]? = nil) {
        guard isErrorsEnabled else { return }
        self.writeError(
            domain: String(describing: type(of: error)),
            code: 0,
            message: error.localizedDescription,
            customAttributes: data,
            labels: labels
        )
    }

    func reportErrorWith(message: String, data: [String: Any]?, labels: [String: Any]? = nil) {
        guard isErrorsEnabled else { return }
        self.log(severity: CoralogixLogSeverity.error, message: message, data: data, labels: labels)
    }
    
    // MARK: - Used By Flutter (symbolicated)
    func reportErrorWith(message: String, stackTrace: String?) {
        let stackTraceJson = stackTrace.flatMap {
            let stackTraceArray = Helper.parseStackTrace($0)
            return Helper.convertArrayToJsonString(array: stackTraceArray)
        }
        reportErrorInternal(message: message, stackTraceJson: stackTraceJson)
    }

    // MARK: - Used By Flutter (obfuscated)
    func reportErrorWith(message: String,
                         obfuscatedStackTrace: [String],
                         arch: String?,
                         buildId: String?,
                         stackTraceType: String?,
                         customAttributes: [String: Any]? = nil,
                         labels: [String: Any]? = nil) {
        let frames: [[String: Any]] = obfuscatedStackTrace.map { [Keys.virt.rawValue: $0] }
        let stackTraceJson = Helper.convertArrayToJsonString(array: frames)
        reportErrorInternal(message: message,
                            stackTraceJson: stackTraceJson,
                            arch: arch,
                            buildId: buildId,
                            stackTraceType: stackTraceType,
                            customAttributes: customAttributes,
                            labels: labels)
    }

    // MARK: - Used By React Native
    func reportErrorWith(message: String,
                         stackTrace: [[String: Any]],
                         errorType: String?,
                         isCrash: Bool = false,
                         arch: String? = nil,
                         buildId: String? = nil,
                         stackTraceType: String? = nil,
                         customAttributes: [String: Any]? = nil,
                         labels: [String: Any]? = nil) {
        let stackTraceJson = Helper.convertArrayToJsonString(array: stackTrace)
        reportErrorInternal(message: message,
                            stackTraceJson: stackTraceJson,
                            errorType: errorType,
                            isCrash: isCrash,
                            arch: arch,
                            buildId: buildId,
                            stackTraceType: stackTraceType,
                            customAttributes: customAttributes,
                            labels: labels)
    }

    private func reportErrorInternal(message: String,
                                     stackTraceJson: String?,
                                     errorType: String? = nil,
                                     isCrash: Bool = false,
                                     arch: String? = nil,
                                     buildId: String? = nil,
                                     stackTraceType: String? = nil,
                                     customAttributes: [String: Any]? = nil,
                                     labels: [String: Any]? = nil) {
        guard isErrorsEnabled else { return }
        var persistedEventId: String?
        if isCrash {
            // Persisted BEFORE the span is created: the process is usually about to
            // die, and only a disk write is guaranteed to finish in time. The stored
            // copy is removed once an upload is confirmed — or re-sent next launch.
            persistedEventId = self.persistCrashEvent(message: message,
                                                      stackTraceJson: stackTraceJson,
                                                      errorType: errorType,
                                                      arch: arch,
                                                      buildId: buildId,
                                                      stackTraceType: stackTraceType,
                                                      customAttributes: customAttributes,
                                                      labels: labels)
        }
        // A crash report may precede process death — don't leave the event in the batch queue
        // (up to 2s) where it would die with the process. Sequenced on the span actually having
        // ended, because a live crash now waits for its screenshot: flushing before that would
        // miss the very event it was called for. If the process does die first, the copy
        // persisted above is re-sent next launch, which is the same net as a failed flush.
        // Remove only THIS event, and only once ITS OWN upload is confirmed: the store may hold
        // an unconfirmed backlog from a previous launch, and an earlier crash's success must not
        // delete a later crash that failed.
        let flushCrash: (() -> Void)? = isCrash ? { [weak self] in
            self?.flush { [weak self] in
                guard let self, let persistedEventId,
                      self.coralogixExporter?.didConfirmCrashUpload(id: persistedEventId) == true else { return }
                self.crashEventStore.remove(ids: [persistedEventId])
            }
        } : nil

        self.writeError(
            domain: "",
            message: message,
            stackTraceJson: stackTraceJson,
            errorType: errorType,
            isCrash: isCrash,
            arch: arch,
            buildId: buildId,
            stackTraceType: stackTraceType,
            customAttributes: customAttributes,
            labels: labels,
            crashEventId: persistedEventId,
            then: flushCrash
        )
    }

    private func persistCrashEvent(message: String,
                                   stackTraceJson: String?,
                                   errorType: String?,
                                   arch: String?,
                                   buildId: String?,
                                   stackTraceType: String?,
                                   customAttributes: [String: Any]?,
                                   labels: [String: Any]?) -> String {
        var event: [String: Any] = [
            Keys.errorMessage.rawValue: message,
            Keys.crashTimestamp.rawValue: String(Date().timeIntervalSince1970.milliseconds)
        ]
        if let stackTraceJson { event[Keys.stackTrace.rawValue] = stackTraceJson }
        if let errorType { event[Keys.errorType.rawValue] = errorType }
        if let arch { event[Keys.arch.rawValue] = arch }
        if let buildId { event[Keys.buildId.rawValue] = buildId }
        if let stackTraceType { event[Keys.stackTraceType.rawValue] = stackTraceType }
        // Stored as a JSON string (not the raw dictionary): callers can pass values
        // JSONSerialization rejects (e.g. Date), which would abort the whole store
        // write and silently drop the crash backup.
        if let json = Helper.jsonAttributeString(dict: customAttributes) {
            event[Keys.data.rawValue] = json
        }
        if let json = Helper.jsonAttributeString(dict: labels) {
            event[Keys.customLabels.rawValue] = json
        }
        return crashEventStore.append(event)
    }

    /// Re-emits crash events persisted by a previous process whose upload was never
    /// confirmed — the hybrid analogue of PLCrashReporter's pending report. Emits
    /// spans only; upload confirmation and store clearing happen in
    /// `completeCrashRecovery()` once init has finished. The re-emitted event keeps
    /// the original `crash_timestamp`; session attribution follows the same
    /// prev-session stitching as PLCR crash reports.
    internal func resendPendingStoredCrashEvents() {
        let pending = crashEventStore.loadAll()
        guard !pending.isEmpty else { return }
        for event in pending {
            self.writeError(
                domain: "",
                message: event[Keys.errorMessage.rawValue] as? String ?? "",
                stackTraceJson: event[Keys.stackTrace.rawValue] as? String,
                errorType: event[Keys.errorType.rawValue] as? String,
                isCrash: true,
                arch: event[Keys.arch.rawValue] as? String,
                buildId: event[Keys.buildId.rawValue] as? String,
                stackTraceType: event[Keys.stackTraceType.rawValue] as? String,
                customAttributes: (event[Keys.data.rawValue] as? String)
                    .flatMap { Helper.convertJsonStringToDict(jsonString: $0) },
                labels: (event[Keys.customLabels.rawValue] as? String)
                    .flatMap { Helper.convertJsonStringToDict(jsonString: $0) },
                crashTimestamp: event[Keys.crashTimestamp.rawValue] as? String,
                crashEventId: event[CrashEventStore.eventIdKey] as? String,
                isRecoveredEvent: true
            )
        }
        let resentIds = Set(pending.compactMap { $0[CrashEventStore.eventIdKey] as? String })
        crashRecoveryLock.lock()
        self.pendingRecoveryCrashEventIds = resentIds
        crashRecoveryLock.unlock()
    }

    func logWith(severity: CoralogixLogSeverity,
                 message: String,
                 data: [String: Any]?,
                 labels: [String: Any]?) {
        guard isCustomOrLifecycleEnabled else { return }
        let span = self.makeSpan(event: .log, source: .code, severity: severity)
        span.setAttribute(key: Keys.message.rawValue, value: message)
        
        if let labels = labels {
            span.setAttribute(key: Keys.customLabels.rawValue, value: Helper.convertDictionaryToJsonString(dict: labels))
        }
        
        if let data = data {
            span.setAttribute(key: Keys.data.rawValue, value: Helper.convertDictionaryToJsonString(dict: data))
        }
                
        guard severity == .error else {
            span.end()
            return
        }
        self.recordScreenshotForSpan(on: span) { _ in span.end() }
    }
    
    // MARK: - Helpers

    /// Captures a session-replay frame for `span`, stamps `screenshotId`/`page` onto it only if a
    /// frame actually shipped, and then calls `finish` — with `true` when the span now points at a
    /// real frame. `finish` runs exactly once, including when session replay is not initialised, so
    /// it is where the caller ends the span.
    ///
    /// Asynchronous because that is when the outcome is known: the native path encodes off the main
    /// thread, and the Flutter path waits for Dart to answer. Stamping before the answer arrives is
    /// what let a span advertise a screenshot for a frame that was dropped — and whose index was
    /// handed back to the next capture, so the attributes pointed at a different frame entirely.
    ///
    /// `extraProperties` carries per-event capture metadata (a tap's coordinates, for instance);
    /// the minted screenshot location wins on any key collision.
    internal func recordScreenshotForSpan(on span: any Span,
                                          extraProperties: [String: Any] = [:],
                                          then finish: @escaping (Bool) -> Void) {
        guard let sessionReplay = SdkManager.shared.getSessionReplay(),
              let coralogixExporter = self.coralogixExporter else {
            Log.d("[SessionReplay] not initialized — span carries no screenshot attributes")
            finish(false)
            return
        }
        let screenshotLocation = coralogixExporter.getScreenshotManager().nextScreenshotLocation
        let properties = buildMetadata(properties: extraProperties, screenshotLocation: screenshotLocation)
        sessionReplay.captureEvent(properties: properties) { [weak self] result in
            // `true` has to mean the span really carries the attributes. If this instance went
            // away between the request and the answer — shutdown, re-init — the stamp is skipped,
            // and reporting success anyway would end a screenshot span pointing at nothing.
            guard let self = self, case .success = result else {
                finish(false)
                return
            }
            self.applyScreenshotAttributes(screenshotLocation, to: span)
            finish(true)
        }
    }

    @available(*, deprecated, message: "Use applyScreenshotAttributes(_:to:) taking a non-inout `any Span`. Span is a class-bound protocol, so the inout achieves nothing.")
    public func applyScreenshotAttributes(_ location: ScreenshotLocation, to span: inout any Span) {
        applyScreenshotAttributes(location, to: span as any Span)
    }

    internal func applyScreenshotAttributes(_ location: ScreenshotLocation, to span: any Span) {
        span.setAttribute(key: Keys.screenshotId.rawValue, value: location.screenshotId)
        span.setAttribute(key: Keys.page.rawValue,         value: location.page)
    }
    
    /// `then` fires once the span has ended, which for a live error is after its screenshot
    /// resolves. The crash force-flush is sequenced on it: a span that ends after the flush
    /// misses the batch it was written for.
    private func writeError(domain: String, code: Int? = nil, message: String,
                            userInfo: [String: Any]? = nil,
                            stackTraceJson: String? = nil,
                            errorType: String? = nil,
                            isCrash: Bool = false,
                            arch: String? = nil,
                            buildId: String? = nil,
                            stackTraceType: String? = nil,
                            customAttributes: [String: Any]? = nil,
                            labels: [String: Any]? = nil,
                            crashTimestamp: String? = nil,
                            crashEventId: String? = nil,
                            isRecoveredEvent: Bool = false,
                            then: (() -> Void)? = nil) {
        // `crashTimestamp` is set only for events recovered from CrashEventStore on
        // the launch after a crash. Anchor those to the original crash time and to
        // the session that was live when the process died — the same attribution
        // PLCrashReporter reports get in processPendingCrashReport. Without it the
        // event would surface under the relaunch time and the recovery session.
        let recoveredCrashDate = crashTimestamp
            .flatMap { Double($0) }
            .map { Date(timeIntervalSince1970: $0 / 1000.0) }
        let span = makeSpan(event: .error, source: .console, severity: .error, startTime: recoveredCrashDate)
        if recoveredCrashDate != nil {
            self.overrideSessionForCrashedSession(on: span)
        }
        span.setAttribute(key: Keys.domain.rawValue, value: domain)
        if let code { span.setAttribute(key: Keys.code.rawValue, value: code) }
        span.setAttribute(key: Keys.errorMessage.rawValue, value: message)
        span.setAttribute(key: Keys.isCrash.rawValue, value: isCrash)
        // Correlation id for per-event upload confirmation (read by the exporter,
        // not mapped into cx_rum, so it stays off the wire).
        if let crashEventId {
            span.setAttribute(key: Keys.crashEventId.rawValue, value: crashEventId)
        }
        if let crashTimestamp, !crashTimestamp.isEmpty {
            span.setAttribute(key: Keys.crashTimestamp.rawValue, value: crashTimestamp)
        }
        if let errorType { span.setAttribute(key: Keys.errorType.rawValue, value: errorType) }
        if let stackTraceJson { span.setAttribute(key: Keys.stackTrace.rawValue, value: stackTraceJson) }
        if let userInfo, !userInfo.isEmpty {
            span.setAttribute(key: Keys.userInfo.rawValue, value: Helper.convertDictionaryToJsonString(dict: userInfo))
        }
        if let arch, !arch.isEmpty { span.setAttribute(key: Keys.arch.rawValue, value: arch) }
        if let buildId, !buildId.isEmpty { span.setAttribute(key: Keys.buildId.rawValue, value: buildId) }
        if let stackTraceType, !stackTraceType.isEmpty { span.setAttribute(key: Keys.stackTraceType.rawValue, value: stackTraceType) }
        if let json = Helper.jsonAttributeString(dict: customAttributes) {
            span.setAttribute(key: Keys.data.rawValue, value: json)
        }
        if let json = Helper.jsonAttributeString(dict: labels) {
            span.setAttribute(key: Keys.customLabels.rawValue, value: json)
        }
        // Note: hybrid error paths (Flutter/RN) intentionally omit the code attribute — there is
        // no meaningful error code in these contexts. Native paths pass an explicit code when relevant.
        let endSpan = {
            if let recoveredCrashDate {
                span.end(time: recoveredCrashDate)
            } else {
                span.end()
            }
            then?()
        }

        // An event replayed from CrashEventStore takes no screenshot. It is re-emitted on the
        // launch *after* the crash, so the only frame available shows this launch's screen —
        // attached to an event dated to the previous session, it would be actively misleading.
        //
        // Asked as its own question rather than inferred from `recoveredCrashDate`. That date
        // answers *when* to anchor the span, and it is nil whenever the persisted timestamp is
        // missing, empty or unparsable — the store keeps any record whose outer JSON is an array,
        // so a malformed one would have replayed and captured the relaunch screen.
        //
        // `isCrash` is not this question either. It is a caller-supplied flag on a public entry
        // point, and the documented hybrid path — an RN or Flutter host reporting a JS or Dart
        // fatal — passes it while the native process carries on. Skipping there would throw away
        // the frame from the moment of failure, which for a hybrid fatal is the most useful
        // artifact there is. The force-flush this guard once existed to protect is sequenced on
        // `then` instead, so the span is in the batch before the flush runs either way.
        guard !isRecoveredEvent else {
            endSpan()
            return
        }

        recordScreenshotForSpan(on: span) { _ in endSpan() }
    }
}
