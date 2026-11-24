//
//  ErrorInstrumentation.swift
//  
//
//  Created by Coralogix DEV TEAM on 07/04/2024.
//

import Foundation

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
            source: .captured,
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
            source: .captured,
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
            source: .captured,
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
    
    // MARK: - Used By Flutter (obfuscated)
    func reportErrorWith(message: String,
                         obfuscatedStackTrace: [String],
                         arch: String?,
                         buildId: String?,
                         stackTraceType: String?,
                         customAttributes: [String: Any]? = nil,
                         labels: [String: Any]? = nil,
                         isCrash: Bool = false,
                         source: String? = nil) {
        let frames: [[String: Any]] = obfuscatedStackTrace.map { [Keys.virt.rawValue: $0] }
        let stackTraceJson = Helper.convertArrayToJsonString(array: frames)
        reportErrorInternal(message: message,
                            hybridSource: source,
                            stackTraceJson: stackTraceJson,
                            isCrash: isCrash,
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
                         labels: [String: Any]? = nil,
                         source: String? = nil) {
        let stackTraceJson = Helper.convertArrayToJsonString(array: stackTrace)
        reportErrorInternal(message: message,
                            hybridSource: source,
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
                                     hybridSource: String?,
                                     stackTraceJson: String?,
                                     errorType: String? = nil,
                                     isCrash: Bool = false,
                                     arch: String? = nil,
                                     buildId: String? = nil,
                                     stackTraceType: String? = nil,
                                     customAttributes: [String: Any]? = nil,
                                     labels: [String: Any]? = nil) {
        guard isErrorsEnabled else { return }
        let source = EventSource.hybrid(hybridSource)
        let fields = ErrorFields(domain: "",
                                 message: message,
                                 isCrash: isCrash,
                                 errorType: errorType,
                                 stackTraceJson: stackTraceJson,
                                 arch: arch,
                                 buildId: buildId,
                                 stackTraceType: stackTraceType,
                                 dataJson: Helper.jsonAttributeString(dict: customAttributes),
                                 labelsJson: Helper.jsonAttributeString(dict: labels))
        // A crash report may precede process death, so what the batch queue holds (up to 2s) is
        // flushed rather than left to die with the process.
        let flushCrash: (() -> Void)? = isCrash ? { [weak self] in self?.flush() } : nil
        // React Native's own fatal handler: the same process is about to end in a native crash
        // report of this error. The error is sent now and kept on disk, and the next launch drops
        // that report (`JsFatalRecovery`). One that cannot be kept goes the usual way below.
        if isCrash, source == .crash, CoralogixRum.mobileSDK.sdkFramework.isReactNative,
           self.reportReactNativeFatal(fields) {
            flushCrash?()
            return
        }
        // Sequenced on the span having ended. Nothing is kept on disk: as on Android, any other hybrid crash whose upload fails is not re-sent.
        self.writeError(source: source, fields: fields, then: flushCrash)
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

        span.end()
    }
    
    /// `then` fires once the span has ended. The crash force-flush is sequenced on it: a span that
    /// ends after the flush misses the batch it was written for.
    private func writeError(source: EventSource,
                            domain: String, code: Int? = nil, message: String,
                            userInfo: [String: Any]? = nil,
                            stackTraceJson: String? = nil,
                            errorType: String? = nil,
                            isCrash: Bool = false,
                            arch: String? = nil,
                            buildId: String? = nil,
                            stackTraceType: String? = nil,
                            customAttributes: [String: Any]? = nil,
                            labels: [String: Any]? = nil) {
        let userInfoJson = userInfo.flatMap { $0.isEmpty ? nil : Helper.convertDictionaryToJsonString(dict: $0) }
        let fields = ErrorFields(domain: domain,
                                 code: code,
                                 message: message,
                                 isCrash: isCrash,
                                 errorType: errorType,
                                 stackTraceJson: stackTraceJson,
                                 userInfoJson: userInfoJson,
                                 arch: arch,
                                 buildId: buildId,
                                 stackTraceType: stackTraceType,
                                 dataJson: Helper.jsonAttributeString(dict: customAttributes),
                                 labelsJson: Helper.jsonAttributeString(dict: labels))
        writeError(source: source, fields: fields)
    }

    private func writeError(source: EventSource, fields: ErrorFields, then: (() -> Void)? = nil) {
        let span = makeSpan(event: .error, source: source, severity: .error)
        fields.apply(to: span)
        span.end()
        then?()
    }
}

/// An error's own attributes, as every error span carries them. Codable so a React Native fatal
/// kept for the next launch is sent with exactly the attributes it would have been sent with live.
struct ErrorFields: Codable, Equatable {
    var domain: String
    /// Hybrid errors (Flutter, React Native) leave it out: they have no meaningful error code.
    var code: Int? = nil
    var message: String
    var isCrash: Bool
    var errorType: String? = nil
    var stackTraceJson: String? = nil
    var userInfoJson: String? = nil
    var arch: String? = nil
    var buildId: String? = nil
    var stackTraceType: String? = nil
    var dataJson: String? = nil
    var labelsJson: String? = nil

    func apply(to span: any Span) {
        span.setAttribute(key: Keys.domain.rawValue, value: domain)
        if let code { span.setAttribute(key: Keys.code.rawValue, value: code) }
        span.setAttribute(key: Keys.errorMessage.rawValue, value: message)
        span.setAttribute(key: Keys.isCrash.rawValue, value: isCrash)
        func set(_ key: Keys, _ value: String?, omitEmpty: Bool = false) {
            guard let value, !(omitEmpty && value.isEmpty) else { return }
            span.setAttribute(key: key.rawValue, value: value)
        }
        set(.errorType, errorType)
        set(.stackTrace, stackTraceJson)
        set(.userInfo, userInfoJson)
        // An empty arch, build id or stack-trace type is left out.
        set(.arch, arch, omitEmpty: true)
        set(.buildId, buildId, omitEmpty: true)
        set(.stackTraceType, stackTraceType, omitEmpty: true)
        set(.data, dataJson)
        set(.customLabels, labelsJson)
    }
}
