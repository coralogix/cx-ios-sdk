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
    
    func reportErrorWith(exception: NSException) {
        guard isErrorsEnabled else { return }
        let userInfo = Helper.convertDictionary(exception.userInfo ?? [:])
        self.writeError(
            domain: exception.name.rawValue,
            code: 0,
            message: exception.reason ?? "",
            userInfo: userInfo
        )
    }
    
    func reportErrorWith(error: NSError) {
        guard isErrorsEnabled else { return }
        self.writeError(
            domain: error.domain,
            code: error.code,
            message: error.localizedDescription,
            userInfo: error.userInfo
        )
    }
    
    func reportErrorWith(error: Error) {
        guard isErrorsEnabled else { return }
        self.writeError(
            domain: String(describing: type(of: error)),
            code: 0,
            message: error.localizedDescription
        )
    }

    func reportErrorWith(message: String, data: [String: Any]?) {
        guard isErrorsEnabled else { return }
        self.log(severity: CoralogixLogSeverity.error, message: message, data: data)
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
                         customAttributes: [String: Any]? = nil) {
        let frames: [[String: Any]] = obfuscatedStackTrace.map { [Keys.virt.rawValue: $0] }
        let stackTraceJson = Helper.convertArrayToJsonString(array: frames)
        reportErrorInternal(message: message,
                            stackTraceJson: stackTraceJson,
                            arch: arch,
                            buildId: buildId,
                            stackTraceType: stackTraceType,
                            customAttributes: customAttributes)
    }

    // MARK: - Used By React Native
    func reportErrorWith(message: String,
                         stackTrace: [[String: Any]],
                         errorType: String?,
                         isCrash: Bool = false,
                         arch: String? = nil,
                         buildId: String? = nil,
                         stackTraceType: String? = nil,
                         customAttributes: [String: Any]? = nil) {
        let stackTraceJson = Helper.convertArrayToJsonString(array: stackTrace)
        reportErrorInternal(message: message,
                            stackTraceJson: stackTraceJson,
                            errorType: errorType,
                            isCrash: isCrash,
                            arch: arch,
                            buildId: buildId,
                            stackTraceType: stackTraceType,
                            customAttributes: customAttributes)
    }

    private func reportErrorInternal(message: String,
                                     stackTraceJson: String?,
                                     errorType: String? = nil,
                                     isCrash: Bool = false,
                                     arch: String? = nil,
                                     buildId: String? = nil,
                                     stackTraceType: String? = nil,
                                     customAttributes: [String: Any]? = nil) {
        guard isErrorsEnabled else { return }
        if isCrash {
            // Persisted BEFORE the span is created: the process is usually about to
            // die, and only a disk write is guaranteed to finish in time. The stored
            // copy is cleared once an upload is confirmed — or re-sent next launch.
            self.persistCrashEvent(message: message,
                                   stackTraceJson: stackTraceJson,
                                   errorType: errorType,
                                   arch: arch,
                                   buildId: buildId,
                                   stackTraceType: stackTraceType,
                                   customAttributes: customAttributes)
        }
        self.writeError(
            domain: "",
            message: message,
            stackTraceJson: stackTraceJson,
            errorType: errorType,
            isCrash: isCrash,
            arch: arch,
            buildId: buildId,
            stackTraceType: stackTraceType,
            customAttributes: customAttributes
        )
        if isCrash {
            // A crash report usually precedes process death — don't leave the event
            // in the batch queue (up to 2s) where it would die with the process.
            self.flush { [weak self] in
                guard let self, self.coralogixExporter?.didUploadCrashEvents == true else { return }
                self.crashEventStore.clear()
            }
        }
    }

    private func persistCrashEvent(message: String,
                                   stackTraceJson: String?,
                                   errorType: String?,
                                   arch: String?,
                                   buildId: String?,
                                   stackTraceType: String?,
                                   customAttributes: [String: Any]?) {
        var event: [String: Any] = [
            Keys.errorMessage.rawValue: message,
            Keys.crashTimestamp.rawValue: String(Date().timeIntervalSince1970.milliseconds)
        ]
        if let stackTraceJson { event[Keys.stackTrace.rawValue] = stackTraceJson }
        if let errorType { event[Keys.errorType.rawValue] = errorType }
        if let arch { event[Keys.arch.rawValue] = arch }
        if let buildId { event[Keys.buildId.rawValue] = buildId }
        if let stackTraceType { event[Keys.stackTraceType.rawValue] = stackTraceType }
        if let customAttributes { event[Keys.data.rawValue] = customAttributes }
        crashEventStore.append(event)
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
                customAttributes: event[Keys.data.rawValue] as? [String: Any],
                crashTimestamp: event[Keys.crashTimestamp.rawValue] as? String
            )
        }
        self.didEmitStoredCrashEvents = true
    }

    func logWith(severity: CoralogixLogSeverity,
                 message: String,
                 data: [String: Any]?,
                 labels: [String: Any]?) {
        guard isCustomOrLifecycleEnabled else { return }
        var span = self.makeSpan(event: .log, source: .code, severity: severity)
        span.setAttribute(key: Keys.message.rawValue, value: message)
        
        if let labels = labels {
            span.setAttribute(key: Keys.customLabels.rawValue, value: Helper.convertDictionaryToJsonString(dict: labels))
        }
        
        if let data = data {
            span.setAttribute(key: Keys.data.rawValue, value: Helper.convertDictionaryToJsonString(dict: data))
        }
                
        if severity == .error { self.recordScreenshotForSpan(to: &span) }
        span.end()
    }
    
    // MARK: - Helpers
    internal func recordScreenshotForSpan(to span: inout any Span) {
        if let sessionReplay = SdkManager.shared.getSessionReplay(),
           let coralogixExporter = self.coralogixExporter {
            let screenshotLocation = coralogixExporter.getScreenshotManager().nextScreenshotLocation
            let result = recordSessionReplayEvent(for: screenshotLocation, via: sessionReplay)
            switch result {
            case .failure(let error):
                if error == .skippingEvent {
                    coralogixExporter.getScreenshotManager().revertScreenshotCounter()
                }
            case .success():
                applyScreenshotAttributes(screenshotLocation, to: &span)
            }
        }
    }
    
    public func applyScreenshotAttributes(_ location: ScreenshotLocation, to span: inout any Span) {
        span.setAttribute(key: Keys.screenshotId.rawValue, value: location.screenshotId)
        span.setAttribute(key: Keys.page.rawValue,         value: location.page)
    }
    
    internal func recordSessionReplayEvent(for location: ScreenshotLocation, via sessionReplay: SessionReplayInterface) -> Result<Void, CaptureEventError> {
        return sessionReplay.captureEvent(properties: location.toProperties())
    }
    
    private func writeError(domain: String, code: Int? = nil, message: String,
                            userInfo: [String: Any]? = nil,
                            stackTraceJson: String? = nil,
                            errorType: String? = nil,
                            isCrash: Bool = false,
                            arch: String? = nil,
                            buildId: String? = nil,
                            stackTraceType: String? = nil,
                            customAttributes: [String: Any]? = nil,
                            crashTimestamp: String? = nil) {
        // `crashTimestamp` is set only for events recovered from CrashEventStore on
        // the launch after a crash. Anchor those to the original crash time and to
        // the session that was live when the process died — the same attribution
        // PLCrashReporter reports get in processPendingCrashReport. Without it the
        // event would surface under the relaunch time and the recovery session.
        let recoveredCrashDate = crashTimestamp
            .flatMap { Double($0) }
            .map { Date(timeIntervalSince1970: $0 / 1000.0) }
        var span = makeSpan(event: .error, source: .console, severity: .error, startTime: recoveredCrashDate)
        if recoveredCrashDate != nil {
            self.overrideSessionForCrashedSession(on: span)
        }
        span.setAttribute(key: Keys.domain.rawValue, value: domain)
        if let code { span.setAttribute(key: Keys.code.rawValue, value: code) }
        span.setAttribute(key: Keys.errorMessage.rawValue, value: message)
        span.setAttribute(key: Keys.isCrash.rawValue, value: isCrash)
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
        // Note: hybrid error paths (Flutter/RN) intentionally omit the code attribute — there is
        // no meaningful error code in these contexts. Native paths pass an explicit code when relevant.
        recordScreenshotForSpan(to: &span)
        if let recoveredCrashDate {
            span.end(time: recoveredCrashDate)
        } else {
            span.end()
        }
    }
}
