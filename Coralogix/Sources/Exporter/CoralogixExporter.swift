//
//  CoralogixExporter.swift
//
//  Created by Coralogix DEV TEAM on 27/03/2024.
//

import Foundation
import CoralogixInternal

public class CoralogixExporter: SpanExporter {
    // Written from the caller's thread (set(labels:), setUserContext, setApplicationContext) and
    // read on the span-processing queue and main thread. Copying the struct while another thread
    // replaces its labels dictionary over-releases the storage, so every access takes the lock.
    // Read through getOptions() only; never touch _options directly.
    private var _options: CoralogixExporterOptions
    private let optionsLock = NSLock()

    // Not re-entrant: `body` must not call getOptions().
    private func mutateOptions(_ body: (inout CoralogixExporterOptions) -> Void) {
        optionsLock.lock()
        defer { optionsLock.unlock() }
        body(&_options)
    }
    private var viewManager: ViewManager
    private var sessionManager: SessionManager
    private var networkManager: NetworkProtocol
    private var metricsManager: MetricsManager
    private var screenshotManager = ScreenshotManager()
    lazy var spanUploader: SpanUploading = SpanUploader(options: self.getOptions())

    private let spanProcessingQueue = DispatchQueue(label: Keys.queueSpanProcessingQueue.rawValue)

    /// Per-session sampling decision. `true` while the SDK should export the current session's
    /// non-excluded events; `false` while only events listed in `options.excludeFromSampling`
    /// should pass. Rerolled on every session rotation by `CoralogixRum`.
    private var currentSessionSampledIn: Bool = true
    private let samplingStateLock = NSLock()

    /// Correlation ids (`crash_event_id`) of crash events whose upload was confirmed
    /// in this process. Confirmation is per-event, not a process-wide flag: a crash
    /// is only removed from disk / its PLCrashReporter report purged once THAT crash's
    /// own upload succeeded, so a later failed crash can't be dropped just because an
    /// earlier one delivered.
    private var confirmedCrashEventIds: Set<String> = []
    private let crashUploadLock = NSLock()

    func didConfirmCrashUpload(id: String) -> Bool {
        crashUploadLock.lock()
        defer { crashUploadLock.unlock() }
        return confirmedCrashEventIds.contains(id)
    }

    private func recordCrashUpload(ids: Set<String>, succeeded: Bool) {
        guard succeeded, !ids.isEmpty else { return }
        crashUploadLock.lock()
        confirmedCrashEventIds.formUnion(ids)
        crashUploadLock.unlock()
    }

    /// Resolves the crash spans this exporter itself declined to send — dropped by session
    /// sampling or by `ignoreErrors` — by recording their ids as confirmed. "Confirmed" here
    /// means the report is finished with, whether by delivery or by policy: `completeCrashRecovery`
    /// gates the purge of a pending PLCrashReporter report, and `CrashEventStore` its removal, on
    /// that flag alone. Without this a crash from a sampled-out session is re-parsed, re-emitted
    /// and re-dropped on every launch until another crash overwrites the file. The idle-session
    /// early return is deliberately not routed here: that is a deferral, and retrying it on the
    /// next launch is the right outcome.
    private func resolveCrashSpansDroppedByPolicy(incoming: Set<String>, surviving spans: [SpanData]) {
        let dropped = incoming.subtracting(crashEventIds(in: spans))
        recordCrashUpload(ids: dropped, succeeded: true)
    }

    /// Correlation ids of the crash events in this batch, read from the raw span
    /// attribute. The attribute is not mapped into cx_rum, so it stays off the wire.
    private func crashEventIds(in spans: [SpanData]) -> Set<String> {
        var ids: Set<String> = []
        for span in spans {
            // Keyed on the correlation id alone: it is stamped only on crash spans, by both
            // paths, and only where a confirmation is awaited. Gating on is_crash as well
            // would miss the PLCrashReporter path, which never sets that attribute.
            guard let id = span.getAttribute(forKey: Keys.crashEventId.rawValue) as? String else {
                continue
            }
            ids.insert(id)
        }
        return ids
    }

    public init(options: CoralogixExporterOptions,
                sessionManager: SessionManager,
                networkManager: NetworkProtocol,
                viewManager: ViewManager,
                metricsManager: MetricsManager) {
        self._options = options
        self.sessionManager = sessionManager
        self.networkManager = networkManager
        self.viewManager = viewManager
        self.metricsManager = metricsManager
        
        self.sessionManager.viewProvider = { [weak self] in
            self?.viewManager.currentView ?? (nil, nil)
        }
        self.sessionManager.sessionEndedCallback = { [weak self] in
            self?.viewManager.reset()
            self?.sessionManager.reset()
            self?.screenshotManager.reset()
        }
    }
    
    var pendingSpans: [SpanData] = []
    var endPoint: String {
      return "\(getOptions().coralogixDomain.rawValue)\(Global.coralogixPath.rawValue)"
    }
    
    public func getOptions() -> CoralogixExporterOptions {
        optionsLock.lock()
        defer { optionsLock.unlock() }
        return _options
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
        mutateOptions { $0.userContext = userContext }
    }
    
    public func update(labels: [String: Any]) {
        mutateOptions { $0.labels = labels }
    }
    
    public func update(view: ViewManager) {
        self.viewManager = view
    }
    
    public func update(application: String, version: String) {
        mutateOptions {
            $0.version = version
            $0.application = application
        }
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
            sdkVersion: CoralogixRum.mobileSDK.sdkFramework.version
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

        // Per-session sampling: a span stamped sampled-out proceeds only if its event_type is
        // opted into options.excludeFromSampling, or it is `internal` (other than
        // session_replay_init) and that list is non-empty (see `passesSessionSampling`). Paired with the
        // propagate-only network check, which catches the case sampling cannot. Placed above
        // URL/error filters and the tracesExporter callback so hybrid + external OTLP consumers
        // inherit the same behavior.
        // Crash correlation ids present before any filter runs: a crash span this method decides
        // not to send still has to be resolved, see `resolveCrashSpansDroppedByPolicy`.
        let incomingCrashIds = self.crashEventIds(in: spans)

        var filterSpans = spans.filter { self.passesSessionSampling($0) && self.reportsNetworkEvents($0) }
        if filterSpans.count != spans.count {
            Log.d("[CoralogixExporter] export: \(spans.count) in, \(filterSpans.count) after sampling and network-reporting filters")
        }
        if filterSpans.isEmpty {
            resolveCrashSpansDroppedByPolicy(incoming: incomingCrashIds, surviving: [])
            return .success
        }

        // ignore Urls
        filterSpans = filterSpans.filter { self.shouldRemoveSpan(span: $0) }
        if filterSpans.isEmpty {
            resolveCrashSpansDroppedByPolicy(incoming: incomingCrashIds, surviving: [])
            return .failure
        }

        // ignore Error
        filterSpans = filterSpans.filter { self.shouldFilterIgnoreError(span: $0) }
        
        // Deduplicate using spanId as key
        let uniqueSpansDict = Dictionary(grouping: filterSpans, by: { $0.spanId })
        let uniqueSpans = uniqueSpansDict.compactMap { $0.value.first }

        resolveCrashSpansDroppedByPolicy(incoming: incomingCrashIds, surviving: uniqueSpans)

        if !uniqueSpans.isEmpty {
            let options = getOptions()
            // Invoke tracesExporter callback if configured (additive OTLP export path).
            // This provides raw SpanData for external OTLP consumers and does NOT affect
            // the CX log pipeline — instrumentation_data is always preserved.
            if let tracesExporter = options.tracesExporter {
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
            
            // Crash correlation ids present in this batch, read from the raw spans.
            let crashIds = self.crashEventIds(in: uniqueSpans)

            let sdk = CoralogixRum.mobileSDK.sdkFramework
            if !sdk.isNative, let callback = options.beforeSendCallBack {
                // Crash events skip the hybrid JS round trip: when a crash is exported the
                // process is usually about to terminate, and the extra native→JS→native hop
                // loses the race. The hybrid beforeSend callback cannot edit or drop them;
                // the native beforeSend option (applied during encoding) still can.
                let crashSpans = cxSpansDictionary.filter { self.isCrashEvent($0) }
                let editableSpans = cxSpansDictionary.filter { !self.isCrashEvent($0) }

                var result: SpanExporterResultCode = .success
                if !crashSpans.isEmpty {
                    result = spanUploader.upload(crashSpans, endPoint: self.endPoint)
                    recordCrashUpload(ids: crashIds, succeeded: result == .success)
                }
                if !editableSpans.isEmpty {
                    let clonedSpans = editableSpans.deepCopy()
                    callback(clonedSpans)
                }
                return result
            }
            let result = spanUploader.upload(cxSpansDictionary, endPoint: self.endPoint)
            if !crashIds.isEmpty {
                recordCrashUpload(ids: crashIds, succeeded: result == .success)
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
        
        let options = getOptions()
        let metadata = VersionMetadata(appName: options.application,
                                         appVersion: options.version)
        
        // CxSpan init can fail if session attributes are missing
        guard let cxSpan = CxSpan(otel: otelSpan,
                                  versionMetadata: metadata,
                                  sessionManager: self.sessionManager,
                                  networkManager: self.networkManager,
                                  viewManager: self.viewManager,
                                  metricsManager: self.metricsManager,
                                  options: options) else {
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
    /// When the span's own `is_session_sampled_in` stamp is true, every span passes. When it is
    /// false, only spans whose `event_type` matches an opt-in entry in `options.excludeFromSampling`
    /// pass, plus the SDK's own `internal` events (except `session_replay_init`) when that list is
    /// non-empty. Spans missing an `event_type` attribute are dropped when stamped sampled-out.
    /// Internal (rather than private per the ticket) so unit tests can exercise it directly.
    internal func passesSessionSampling(_ span: SpanDataProtocol) -> Bool {
        // The sampling decision belongs to the session the span was created in, not the live one.
        // Read the per-span stamp SessionManager burns at creation rather than the live
        // `currentSessionSampledIn` flag: a span created in a sampled-in session but exported
        // after a rotation to a sampled-out session must still be kept. A missing stamp (older
        // spans) defaults to sampled-in so nothing is dropped by omission.
        let sampledIn = attributeStringValue(forKey: Keys.spanSessionSampledIn.rawValue, span: span).map { $0 == "true" } ?? true
        if sampledIn { return true }

        guard let eventType = attributeStringValue(forKey: Keys.eventType.rawValue, span: span) else {
            return false
        }

        let excludeFromSampling = getOptions().excludeFromSampling

        // Matches the browser SDK: with nothing excluded a sampled-out session exports nothing at
        // all, its own init and session_replay_init included — otherwise those arrive as snapshot
        // events and the session shows up in session lists. Once anything is excluded the session
        // is reporting anyway, so the SDK's own events go with it.
        //
        // This keys on the event type alone and is deliberately not defended against forgery:
        // `CoralogixCustomSpan.setAttribute` accepts any key, so a caller can stamp `internal` on
        // their own span and have it bypass their own sample rate. That follows the SDK's standing
        // position that semantic fields are the caller's responsibility while identity and counters
        // are defended — the only cost here is the caller's own sampling savings, on their own data.
        // Requiring an SDK-private marker alongside the type would close it if that ever changes.
        //
        // session_replay_init is the exception: Session Replay records nothing in a sampled-out
        // session, so announcing a recording there is wrong whatever is excluded.
        if eventType == CoralogixEventType.internalKey.rawValue {
            return !excludeFromSampling.isEmpty
                && attributeStringValue(forKey: Keys.internalEventType.rawValue, span: span) != Keys.sessionReplayInit.rawValue
        }

        return excludeFromSampling.contains { $0.eventType.rawValue == eventType }
    }

    /// Returns `false` for a `network-request` span reported while network instrumentation is off.
    ///
    /// With the option off the native swizzles are never installed, so this only fires for spans a
    /// hybrid wrapper reports through `setNetworkRequestContext` — that bridge is gated on
    /// `isInitialized` alone and never consults the instrumentations map. The sampling filter cannot
    /// catch them either: the session may be sampled in, so they are stamped sampled-in and pass.
    internal func reportsNetworkEvents(_ span: SpanDataProtocol) -> Bool {
        let eventType = attributeStringValue(forKey: Keys.eventType.rawValue, span: span)
        guard eventType == CoralogixEventType.networkRequest.rawValue else { return true }
        return getOptions().shouldInitInstrumentation(instrumentation: .network)
    }

    internal func shouldRemoveSpan(span: SpanDataProtocol) -> Bool {
        // if the closure returns true, the element stays in the result.
        guard let url = attributeStringValue(forKey: SemanticAttributes.httpUrl.rawValue, span: span) else {
            return true
        }

        if !Global.containsMonitoredPath(url) {
            return !Global.isURLIgnored(url, ignoreUrls: getOptions().ignoreUrls)
        }
        return false
    }

    internal func shouldFilterIgnoreError(span: SpanDataProtocol) -> Bool {
        // if the closure returns true, the element stays in the result.
        guard let message = attributeStringValue(forKey: Keys.errorMessage.rawValue, span: span) else {
            return true
        }
        
        guard let ignoreErrors = getOptions().ignoreErrors, !ignoreErrors.isEmpty else { return true }
        if ignoreErrors.contains(message) { return false }
        return !self.isMatchesRegexPattern(string: message, regexs: ignoreErrors)
    }
}
