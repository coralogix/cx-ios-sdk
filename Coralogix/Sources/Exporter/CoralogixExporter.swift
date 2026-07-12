//
//  CoralogixExporter.swift
//
//  Created by Coralogix DEV TEAM on 27/03/2024.
//

import Foundation
import CoralogixInternal

public class CoralogixExporter: SpanExporter {
    private var options: CoralogixExporterOptions
    private var viewManager: ViewManager
    private var sessionManager: SessionManager
    private var networkManager: NetworkProtocol
    private var metricsManager: MetricsManager
    private var screenshotManager = ScreenshotManager()
    lazy var spanUploader: SpanUploading = SpanUploader(options: self.options)

    private let spanProcessingQueue = DispatchQueue(label: Keys.queueSpanProcessingQueue.rawValue)

    /// Per-session sampling decision. `true` while the SDK should export the current session's
    /// non-excluded events; `false` while only events listed in `options.excludeFromSampling`
    /// should pass. Rerolled on every session rotation by `CoralogixRum`.
    private var currentSessionSampledIn: Bool = true
    private let samplingStateLock = NSLock()

    /// `true` once a batch containing at least one crash event (`error_context.is_crash`)
    /// uploaded successfully in this process. CrashInstrumentation consults this to decide
    /// whether the pending PLCrashReporter report may be purged — kept pessimistic on
    /// failure so the report survives on disk and is retried on the next launch.
    private var crashUploadConfirmed = false
    private let crashUploadLock = NSLock()

    var didUploadCrashEvents: Bool {
        crashUploadLock.lock()
        defer { crashUploadLock.unlock() }
        return crashUploadConfirmed
    }

    private func recordCrashUpload(succeeded: Bool) {
        guard succeeded else { return }
        crashUploadLock.lock()
        crashUploadConfirmed = true
        crashUploadLock.unlock()
    }

    public init(options: CoralogixExporterOptions,
                sessionManager: SessionManager,
                networkManager: NetworkProtocol,
                viewManager: ViewManager,
                metricsManager: MetricsManager) {
        self.options = options
        self.sessionManager = sessionManager
        self.networkManager = networkManager
        self.viewManager = viewManager
        self.metricsManager = metricsManager
        
        self.sessionManager.sessionEndedCallback = { [weak self] in
            self?.viewManager.reset()
            self?.sessionManager.reset()
            self?.screenshotManager.reset()
        }
    }
    
    var pendingSpans: [SpanData] = []
    var endPoint: String {
      return "\(self.options.coralogixDomain.rawValue)\(Global.coralogixPath.rawValue)"
    }
    
    public func getOptions() -> CoralogixExporterOptions {
        return self.options
    }
    
    public func getViewManager() -> ViewManager {
        return self.viewManager
    }
    
    public func getScreenshotManager() -> ScreenshotManager {
        return self.screenshotManager
    }
    
    public func getSessionManager() -> SessionManager {
        return self.sessionManager
    }
    
    public func set(cxView: CXView) {
        if cxView.state == .notifyOnAppear {
            self.viewManager.set(cxView: cxView)
        } else if cxView.state == .notifyOnDisappear {
            self.viewManager.set(cxView: nil)
        }
    }
    
    public func update(userContext: UserContext?) {
        self.options.userContext = userContext
    }
    
    public func update(labels: [String: Any]) {
        self.options.labels = labels
    }
    
    public func update(view: ViewManager) {
        self.viewManager = view
    }
    
    public func update(application: String, version: String) {
        self.options.version = version
        self.options.application = application
    }

    /// Updates the per-session sampling decision. Called once at init and again on every session
    /// rotation. The gating logic that drops non-excluded events when `sampledIn == false` is
    /// wired in `export()` separately; this method only stores the decision.
    internal func updateSessionSampling(sampledIn: Bool) {
        samplingStateLock.lock()
        let changed = self.currentSessionSampledIn != sampledIn
        self.currentSessionSampledIn = sampledIn
        samplingStateLock.unlock()
        if changed {
            Log.d("[SDK] sampling decision updated: sampledIn=\(sampledIn)")
        }
    }

    internal func isCurrentSessionSampledIn() -> Bool {
        samplingStateLock.lock()
        defer { samplingStateLock.unlock() }
        return self.currentSessionSampledIn
    }
    
    internal func sendBeforeSendData(data: [[String: Any]]) {
        let rebuilt = data.map { self.rebuildOtelSpanAttributes(in: $0) }
        self.spanUploader.upload(rebuilt, endPoint: self.endPoint)
    }

    /// Hybrid (`beforeSendCallBack`) path: spans are encoded *before* the JS edit and the
    /// edited batch is handed back here to upload verbatim, so `otelSpan.attributes` would
    /// otherwise stay stale while `text.cx_rum` reflects the edit. Rebuild the attributes from
    /// the final (edited) `cx_rum` — the same call the native single-event path makes in
    /// `CxSpan.getDictionary()` — so both destinations of a span carry identical values.
    ///
    /// Rebuilding from the `cx_rum` dict (a lossy view of the `CxRum` struct, e.g.
    /// `CxRumPayloadBuilder` omits `error_context` for non-error events) intentionally matches
    /// what `text.cx_rum` carries: the hybrid path is always "edit in play," so consistency
    /// between the two destinations is the goal, not preserving struct-only fields.
    ///
    /// `page_url`/`page_fragments` are preserved from the encode-time attributes rather than
    /// re-derived from the live `viewManager`: the span belongs to the view active when it was
    /// created, and re-reading here could drift if the native view advanced during the bridge
    /// round-trip.
    /// Events without `instrumentation_data` (anything but network-request / custom-span) are
    /// returned unchanged.
    private func rebuildOtelSpanAttributes(in event: [String: Any]) -> [String: Any] {
        guard var instrumentationData = event[Keys.instrumentationData.rawValue] as? [String: Any],
              var otelSpan = instrumentationData[Keys.otelSpan.rawValue] as? [String: Any],
              let cxRum = (event[Keys.text.rawValue] as? [String: Any])?[Keys.cxRum.rawValue] as? [String: Any] else {
            return event
        }
        let previousAttributes = otelSpan[Keys.attributes.rawValue] as? [String: Any] ?? [:]
        otelSpan[Keys.attributes.rawValue] = OtelSpan.rebuiltAttributes(
            fromCxRumDict: cxRum,
            preservingPageFrom: previousAttributes,
            mobileSdkVersion: CoralogixRum.mobileSDK.sdkFramework.version
        )
        instrumentationData[Keys.otelSpan.rawValue] = otelSpan
        var result = event
        result[Keys.instrumentationData.rawValue] = instrumentationData
        return result
    }
    
    #if DEBUG
    /// Test-only: when set, invoked with spans at the start of export (for integration tests). Not compiled in Release.
    static var testExportCallback: (([SpanData]) -> Void)?
    #endif

    public func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        #if DEBUG
        Self.testExportCallback?(spans)
        #endif
        if self.sessionManager.isIdle {
            Log.d("[SDK] Skipping export, session is idle")
            return .success
        }

        // Per-session sampling: when the current session is sampled out, only spans whose
        // event_type is opted into options.excludeFromSampling proceed. Placed above URL/error
        // filters and the tracesExporter callback so hybrid + external OTLP consumers inherit
        // the same behavior.
        var filterSpans = spans.filter { self.passesSessionSampling($0) }
        if filterSpans.count != spans.count {
            Log.d("[CoralogixExporter] export: \(spans.count) in, \(filterSpans.count) after sampling filter")
        }
        if filterSpans.isEmpty { return .success }

        // ignore Urls
        filterSpans = filterSpans.filter { self.shouldRemoveSpan(span: $0) }
        if filterSpans.isEmpty { return .failure }

        // ignore Error
        filterSpans = filterSpans.filter { self.shouldFilterIgnoreError(span: $0) }
        
        // Deduplicate using spanId as key
        let uniqueSpansDict = Dictionary(grouping: filterSpans, by: { $0.spanId })
        let uniqueSpans = uniqueSpansDict.compactMap { $0.value.first }

        if !uniqueSpans.isEmpty {
            // Invoke tracesExporter callback if configured (additive OTLP export path).
            // This provides raw SpanData for external OTLP consumers and does NOT affect
            // the CX log pipeline — instrumentation_data is always preserved.
            if let tracesExporter = self.options.tracesExporter {
                let exporterData = CoralogixTraceExporterData(spans: uniqueSpans)
                do {
                    try tracesExporter(exporterData)
                } catch {
                    Log.e("[CoralogixExporter] tracesExporter callback threw: \(error)")
                }
            }
            
            let cxSpansDictionary = autoreleasepool {
                encodeSpans(spans: uniqueSpans)
            }
            Log.d("[CoralogixExporter] encodeSpans: \(uniqueSpans.count) in, \(cxSpansDictionary.count) encoded")
            if cxSpansDictionary.isEmpty {
                return .success
            }
            
            let sdk = CoralogixRum.mobileSDK.sdkFramework
            if !sdk.isNative, let callback = self.options.beforeSendCallBack {
                // Crash events skip the hybrid JS round trip: when a crash is exported the
                // process is usually about to terminate, and the extra native→JS→native hop
                // loses the race. They upload verbatim; beforeSend cannot edit or drop them.
                let crashSpans = cxSpansDictionary.filter { self.isCrashEvent($0) }
                let editableSpans = cxSpansDictionary.filter { !self.isCrashEvent($0) }

                var result: SpanExporterResultCode = .success
                if !crashSpans.isEmpty {
                    result = spanUploader.upload(crashSpans, endPoint: self.endPoint)
                    recordCrashUpload(succeeded: result == .success)
                }
                if !editableSpans.isEmpty {
                    let clonedSpans = editableSpans.deepCopy()
                    callback(clonedSpans)
                }
                return result
            }
            let containsCrashEvent = cxSpansDictionary.contains { self.isCrashEvent($0) }
            let result = spanUploader.upload(cxSpansDictionary, endPoint: self.endPoint)
            if containsCrashEvent {
                recordCrashUpload(succeeded: result == .success)
            }
            return result
        }
        return .failure
    }

    /// Whether an encoded span carries `error_context.is_crash == true` — a crash reported
    /// through the hybrid bridge or rebuilt from a pending PLCrashReporter report.
    private func isCrashEvent(_ encodedSpan: [String: Any]) -> Bool {
        guard let text = encodedSpan[Keys.text.rawValue] as? [String: Any],
              let cxRum = text[Keys.cxRum.rawValue] as? [String: Any],
              let errorContext = cxRum[Keys.errorContext.rawValue] as? [String: Any] else {
            return false
        }
        return errorContext[Keys.isCrash.rawValue] as? Bool ?? false
    }

    public func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        return .success
    }
    
    public func shutdown(explicitTimeout: TimeInterval?) {
        self.sessionManager.shutdown()
        self.viewManager.shutdown()
    }
    
    func encodeSpans(spans: [SpanData]) -> [[String: Any]] {
        var encodedSpans: [[String: Any]] = []
        let group = DispatchGroup()
        group.enter()
        spanProcessingQueue.async(flags: .barrier) { [weak self] in
            defer { group.leave() }
            guard let self = self else { return }
            encodedSpans = spans.compactMap { [weak self] span in
                return self?.spanDatatoCxSpan(otelSpan: span)
            }
        }
        group.wait()
        return encodedSpans
    }
 
    private func spanDatatoCxSpan(otelSpan: SpanData) -> [String: Any]? {
        guard otelSpan.spanId.isValid, !otelSpan.attributes.isEmpty else {
            Log.e("Invalid otelSpan: \(otelSpan)")
            return nil
        }
        
        let metatadata = VersionMetadata(appName: self.options.application,
                                         appVersion: self.options.version)
        
        // CxSpan init can fail if session attributes are missing
        guard let cxSpan = CxSpan(otel: otelSpan,
                                  versionMetadata: metatadata,
                                  sessionManager: self.sessionManager,
                                  networkManager: self.networkManager,
                                  viewManager: self.viewManager,
                                  metricsManager: self.metricsManager,
                                  options: self.options) else {
            return nil  // Span will be filtered out by compactMap
        }
        
        return cxSpan.getDictionary()
    }
    
    private func isMatchesRegexPattern(string: String, regexs: [String]) -> Bool {
        // Iterate over the regex patterns
        for regex in regexs {
            do {
                let regex = try NSRegularExpression(pattern: regex, options: [.caseInsensitive])
                let range = NSRange(string.startIndex..., in: string)
                let matchFound = regex.firstMatch(in: string, options: [], range: range) != nil
                return matchFound
            } catch {
                Log.w("Invalid regex pattern: \(regex) — Error: \(error)")
                continue // Skip invalid regex instead of crashing
            }
        }
        
        // Return false if no regex matches the host
        return false
    }
    
    /// Returns the string value of `key` on `span`, supporting both `AttributeValue` and raw
    /// `String` encodings. Returns nil when the attribute is absent or stored as another type.
    private func attributeStringValue(forKey key: String, span: SpanDataProtocol) -> String? {
        let attributes = span.getAttributes()
        if let attrValue = attributes?[key] as? AttributeValue {
            return attrValue.description
        }
        if let rawString = attributes?[key] as? String {
            return rawString
        }
        return nil
    }

    /// Returns `true` if the span should proceed past the per-session sampling filter.
    /// When the session is sampled in, every span passes. When sampled out, only spans whose
    /// `event_type` attribute matches an opt-in entry in `options.excludeFromSampling` pass.
    /// Spans missing an `event_type` attribute are dropped on sampled-out sessions.
    /// Internal (rather than private per the ticket) so unit tests can exercise it directly.
    internal func passesSessionSampling(_ span: SpanDataProtocol) -> Bool {
        if isCurrentSessionSampledIn() { return true }

        guard let eventType = attributeStringValue(forKey: Keys.eventType.rawValue, span: span) else {
            return false
        }
        return options.excludeFromSampling.contains { $0.eventType.rawValue == eventType }
    }

    internal func shouldRemoveSpan(span: SpanDataProtocol) -> Bool {
        // if the closure returns true, the element stays in the result.
        guard let url = attributeStringValue(forKey: SemanticAttributes.httpUrl.rawValue, span: span) else {
            return true
        }

        if !Global.containsMonitoredPath(url) {
            if let ignoreUrlsOrRejexs = self.options.ignoreUrls,
               !ignoreUrlsOrRejexs.isEmpty,
               ignoreUrlsOrRejexs.contains(url) {
                return false
            }

            if let ignoreUrlsOrRejexs = self.options.ignoreUrls,
               !ignoreUrlsOrRejexs.isEmpty {
                let isMatch = Global.isURLMatchesRegexPattern(string: url, regexs: ignoreUrlsOrRejexs)
                return !isMatch
            }
            return true
        }
        return false
    }

    internal func shouldFilterIgnoreError(span: SpanDataProtocol) -> Bool {
        // if the closure returns true, the element stays in the result.
        guard let message = attributeStringValue(forKey: Keys.errorMessage.rawValue, span: span) else {
            return true
        }
        
        if let ignoreErrorsOrRejexs = self.options.ignoreErrors,
           !ignoreErrorsOrRejexs.isEmpty,
           ignoreErrorsOrRejexs.contains(message) {
            return false
        }
        
        if let ignoreErrorsOrRejexs = self.options.ignoreErrors,
           !ignoreErrorsOrRejexs.isEmpty {
            let isMatch = self.isMatchesRegexPattern(string: message, regexs: ignoreErrorsOrRejexs)
            return !isMatch
        }
        
        return true
    }
}
