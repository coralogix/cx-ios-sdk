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
        // A crash report may precede process death, so it is flushed rather than left in the batch
        // queue (up to 2s) to die with the process. Sequenced on the span having ended, since a live
        // crash waits for its screenshot. Nothing is kept on disk: as on Android, a hybrid crash
        // whose upload fails is not re-sent.
        let flushCrash: (() -> Void)? = isCrash ? { [weak self] in self?.flush() } : nil

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
            then: flushCrash
        )
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
                            then: (() -> Void)? = nil) {
        let span = makeSpan(event: .error, source: .console, severity: .error)
        span.setAttribute(key: Keys.domain.rawValue, value: domain)
        if let code { span.setAttribute(key: Keys.code.rawValue, value: code) }
        span.setAttribute(key: Keys.errorMessage.rawValue, value: message)
        span.setAttribute(key: Keys.isCrash.rawValue, value: isCrash)
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
            span.end()
            then?()
        }

        recordScreenshotForSpan(on: span) { _ in endSpan() }
    }
}
