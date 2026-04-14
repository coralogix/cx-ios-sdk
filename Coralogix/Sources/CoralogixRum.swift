import Foundation
@_exported import CoralogixInternal

#if canImport(UIKit)
import UIKit
#endif

extension Notification.Name {
    static let cxRumNotification = Notification.Name("cxRumNotification")
    static let cxRumNotificationUserActions = Notification.Name("cxRumNotificationUserActions")
}

public class CoralogixRum {
    internal var coralogixExporter: CoralogixExporter?
    internal var networkManager = NetworkManager()
    internal var viewManager = ViewManager(keyChain: KeychainManager())
    internal var sessionManager: SessionManager?
    internal var sessionInstrumentation: URLSessionInstrumentation?
    internal var metricsManager = MetricsManager()
    internal let readinessGroup = DispatchGroup()
    internal var isNetworkInstrumentationReady = false
    private let notificationCenter = NotificationCenter.default

    /// Closures from `CoralogixExporterOptions` cached once at
    /// `initializeUserActionsInstrumentation()` to avoid copying the options
    /// struct on every tap event. The struct gives `let` semantics to each
    /// closure even though the container itself must be `var` (set post-init).
    internal struct UserActionsDelegates {
        let shouldSendText: ((UIView, String) -> Bool)?
        let resolveTargetName: ((UIView) -> String?)?
    }
    internal var userActionsDelegates: UserActionsDelegates?

    internal lazy var tracerProvider: () -> Tracer = {
        return OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: Keys.iosSdk.rawValue,
            instrumentationVersion: Global.sdk.rawValue
        )
    }
    
    static var isInitialized = false
    static var mobileSDK: MobileSDK = MobileSDK()

    /// CX-35956: `getCustomTracer()` may succeed only once per SDK lifecycle (`shutdown()` clears).
    private static var customTracerIssued = false
    /// Serializes check-and-set for `customTracerIssued` so concurrent `getCustomTracer()` calls cannot both succeed.
    private static let customTracerIssuanceLock = NSLock()

    /// Resets CX-35956 singleton state when tests reinitialize the SDK in-process without calling `shutdown()`.
    internal static func resetCustomTracerIssuanceForTesting() {
        customTracerIssuanceLock.lock()
        defer { customTracerIssuanceLock.unlock() }
        customTracerIssued = false
    }
    
    public init(
        options: CoralogixExporterOptions,
        sdkFramework: SdkFramework = .swift,
        sessionManager: SessionManager? = SessionManager()
    ){
        CoralogixRum.mobileSDK = MobileSDK(sdkFramework: sdkFramework)
        Log.isDebug = options.debug
        self.sessionManager = sessionManager
        self.displayCoralogixWord()
        
        guard options.sdkSampler.shouldInitialized() else {
            Log.e("Initialization skipped due to sample rate.")
            return
        }
        
        self.startup(options: options)
    }
    
    deinit {
        self.removeNotification()
    }
    
    private func removeNotification() {
        NotificationCenter.default.removeObserver(self, name: .cxRumNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: .cxRumNotificationUserActions, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didFinishLaunchingNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }
    
    private func startup(options: CoralogixExporterOptions) {
        guard let sessionManager = self.sessionManager else {
            Log.e("SessionManager is nil.")
            return
        }
        _ = UserAgentManager.shared.getUserAgent()
        Log.isDebug = options.debug
        
        self.setupCoreModules()
        self.setupExporter(sessionManager: sessionManager, options: options)
        self.setupTracer(applicationName: options.application)
        self.swizzle()
        self.initializeEnabledInstrumentations(using: options)
        self.createInitSpan()
        CoralogixRum.isInitialized = true
    }
    
    private func initializeEnabledInstrumentations(using options: CoralogixExporterOptions) {
        let instrumentationMap: [(CoralogixExporterOptions.InstrumentationType, () -> Void)] = [
            (.lifeCycle, self.initializeLifeCycleInstrumentation),
            (.userActions, self.initializeUserActionsInstrumentation),
            (.network, self.initializeNetworkInstrumentation),
            (.errors, self.initializeCrashInstrumentation),
            (.mobileVitals, self.initializeMobileVitalsInstrumentation),
            (.anr, self.initializeANRInstrumentation)
        ]
        
        for (type, initializer) in instrumentationMap {
            // userActions is special: we install touch swizzles for native spans OR for session replay in hybrid
            // (not just when options.shouldInitInstrumentation(.userActions)), so use Helper instead of the shared path.
            if type == .userActions {
                if Helper.shouldInstallTouchSwizzles(options: options, sdkFramework: CoralogixRum.mobileSDK.sdkFramework) {
                    initializer()
                }
            } else if options.shouldInitInstrumentation(instrumentation: type) {
                initializer()
            }
        }
    }
    
    // MARK: - Tracing
    internal func setupTracer(applicationName: String) {
        guard let exporter = self.coralogixExporter else {
            Log.e("Failed to setup tracer: coralogixExporter is nil")
            return
        }
        
        // Merge with the default Resource so the OTel SDK fields
        // (telemetry.sdk.name, telemetry.sdk.language, telemetry.sdk.version)
        // are preserved alongside service.name.
        let resource = Resource().merging(other: Resource(attributes: [
            ResourceAttributes.serviceName.rawValue: .string(applicationName)
        ]))
        
        let spanProcessor = BatchSpanProcessor(
            spanExporter: exporter,
            scheduleDelay: Double(Global.BatchSpan.scheduleDelay.rawValue),
            maxExportBatchSize: Global.BatchSpan.maxExportBatchSize.rawValue
        )
        
        let tracerProvider = TracerProviderBuilder()
            .with(resource: resource)
            .add(spanProcessor: spanProcessor)
            .build()
        
        OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
    }
    
    private func setupExporter(sessionManager: SessionManager, options: CoralogixExporterOptions) {
        let exporter = CoralogixExporter(
            options: options,
            sessionManager: sessionManager,
            networkManager: self.networkManager,
            viewManager: self.viewManager,
            metricsManager: self.metricsManager
        )
        self.coralogixExporter = exporter
    }
    
    private func setupCoreModules() {
        self.initializeSessionReplay()
        self.initializeNavigationInstrumentation()
        self.metricsManager.metricsManagerClosure = { [weak self] dict in
            self?.sendMobileVitals(dict)
        }
    }
    
    private func swizzle() {
        // Navigation swizzles are always active — they track view lifecycle
        // independently of the userActions instrumentation setting.
        UIViewController.swizzleViewDidAppear
        UIViewController.swizzleViewDidDisappear
        // Touch-event swizzles are installed on demand inside
        // initializeUserActionsInstrumentation() so they are never active
        // when userActions instrumentation is disabled.
    }
    
    // MARK: - Public API
    
    public var labels: [String: Any]? {
        guard CoralogixRum.isInitialized else { return nil }
        return self.options?.labels
    }
    
    public var userContext: UserContext? {
        guard CoralogixRum.isInitialized else { return nil }
        return self.options?.userContext
    }


    /// Updates the user context associated with all subsequent telemetry events.
    ///
    /// Use this to attach or replace identifying information about the current user
    /// (such as user ID, name, or email). Passing `nil` clears the existing user context.
    ///
    /// Notes:
    /// - This call has no effect if the SDK has not been initialized.
    /// - The provided `UserContext` is propagated to the underlying exporter and will
    ///   be applied to future events only; previously sent data is not modified.
    ///
    /// - Parameter userContext: The new user context to associate with telemetry, or `nil` to clear it.
    public func setUserContext(userContext: UserContext?) {
        guard CoralogixRum.isInitialized else { return }
        self.coralogixExporter?.update(userContext: userContext)
    }
    
    public func set(labels: [String: Any]) {
        guard CoralogixRum.isInitialized else { return }
        self.coralogixExporter?.update(labels: labels)
    }
    
    public func reportError(exception: NSException) {
        guard CoralogixRum.isInitialized else { return }
        self.reportErrorWith(exception: exception)
    }
    
    public func reportError(error: NSError) {
        guard CoralogixRum.isInitialized else { return }
        self.reportErrorWith(error: error)
    }
    
    public func reportError(error: Error) {
        guard CoralogixRum.isInitialized else { return }
        self.reportErrorWith(error: error)
    }
    
    public func reportError(message: String, data: [String: Any]?) {
        guard CoralogixRum.isInitialized else { return }
        self.reportErrorWith(message: message, data: data)
    }
    
    public func reportError(message: String,
                            stackTrace: [[String: Any]],
                            errorType: String?,
                            isCrash: Bool = false,
                            arch: String? = nil,
                            buildId: String? = nil,
                            stackTraceType: String? = nil) {
        guard CoralogixRum.isInitialized else { return }
        self.reportErrorWith(message: message,
                             stackTrace: stackTrace,
                             errorType: errorType,
                             isCrash: isCrash,
                             arch: arch,
                             buildId: buildId,
                             stackTraceType: stackTraceType)
    }

    /// Reports a Dart obfuscated error from Flutter.
    ///
    /// Use when the Dart stack trace is not symbolicated — pass raw virtual addresses
    /// extracted from the obfuscated crash output.
    ///
    /// - Parameters:
    ///   - message: The error message.
    ///   - obfuscatedStackTrace: Array of virtual address strings (e.g. `["0x00000000003da15f", ...]`).
    ///   - arch: The CPU architecture (e.g. `"arm64"`).
    ///   - buildId: The Dart snapshot build ID used for symbolication.
    ///   - stackTraceType: The stack trace type (e.g. `"obfuscated"`).
    public func reportError(message: String,
                            obfuscatedStackTrace: [String],
                            arch: String? = nil,
                            buildId: String? = nil,
                            stackTraceType: String? = Keys.obfuscated.rawValue) {
        guard CoralogixRum.isInitialized else { return }
        self.reportErrorWith(message: message,
                             obfuscatedStackTrace: obfuscatedStackTrace,
                             arch: arch,
                             buildId: buildId,
                             stackTraceType: stackTraceType)
    }
    
    public func reportMobileVitalsMeasurement(type: String, metrics: [HybridMetric]) {
        guard CoralogixRum.isInitialized else { return }
        if (CoralogixRum.mobileSDK.sdkFramework.isNative) { return }
        
        var vitalArray = [[String: Any]]()
        metrics.forEach { element in
            let vital = [
                element.name: [
                    Keys.mobileVitalsUnits.rawValue: element.units,
                    Keys.value.rawValue: element.value
                ]
            ]
            vitalArray.append(vital)
        }
        self.sendMobileVitals([type: vitalArray])
    }
    
    public func reportMobileVitalsMeasurement(type: String, value: Double, units: String) {
        guard CoralogixRum.isInitialized else { return }
        if (CoralogixRum.mobileSDK.sdkFramework.isNative) { return }
        
        let vital = [
            type: [
                Keys.mobileVitalsUnits.rawValue: units,
                Keys.value.rawValue: value
            ]
        ]
        
        self.sendMobileVitals(vital)
    }
    
    public func setView(name: String) {
        guard CoralogixRum.isInitialized else { return }
        let cxView = CXView(state: .notifyOnAppear, name: name)
        self.trackNavigation(for: cxView)
    }
    
    public func log(severity: CoralogixLogSeverity,
                    message: String,
                    data: [String: Any]? = nil,
                    labels: [String: Any]? = nil) {
        guard CoralogixRum.isInitialized else { return }
        self.logWith(severity: severity, message: message, data: data, labels: labels)
    }
    
    public func shutdown() {
        CoralogixCustomGlobalSpanRegistry.shared.teardownIfNeeded()
        Self.customTracerIssuanceLock.lock()
        CoralogixRum.customTracerIssued = false
        CoralogixRum.isInitialized = false
        Self.customTracerIssuanceLock.unlock()
        self.coralogixExporter?.shutdown(explicitTimeout: nil)
        self.removeNotification()
        self.metricsManager.removeObservers()
    }
    
    public var isInitialized: Bool { return CoralogixRum.isInitialized }
    
    public var getSessionId: String? { return self.sessionManager?.getSessionMetadata()?.sessionId }
    
    public func setApplicationContext(application: String, version: String) {
        guard CoralogixRum.isInitialized else { return }
        self.coralogixExporter?.update(application: application, version: version)
    }

    /// Reports a network request from a hybrid platform (Flutter / React Native).
    ///
    /// Call this from the hybrid bridge when the hybrid side completes an HTTP request.
    /// The dictionary should contain: `url`, `host`, `method`, `status_code`, `fragments`,
    /// `schema`, `http_response_body_size`; optional `custom_span_id`, `custom_trace_id`.
    public func setNetworkRequestContext(dictionary: [String: Any]) {
        guard CoralogixRum.isInitialized else { return }
        reportHybridNetworkRequest(dictionary)
    }

    /// Reports a user interaction event from a hybrid platform (Flutter / React Native).
    ///
    /// Call this from the hybrid bridge when the hybrid side detects an interaction event
    /// (tap, scroll, swipe). The native `userActions` instrumentation is automatically
    /// disabled when the SDK is initialised in hybrid mode, so this method is the only
    /// source of interaction spans in that configuration.
    ///
    /// The `dictionary` should contain the same keys that the native instrumentation
    /// produces internally:
    /// - `event_name`  (`String`) — `"click"` | `"scroll"` | `"swipe"`
    /// - `target_element` (`String`) — resolved element name
    /// - `element_classes` (`String`, optional) — UIKit class name
    /// - `element_id` (`String`, optional) — accessibility identifier
    /// - `target_element_inner_text` (`String`, optional) — visible label text
    /// - `scroll_direction` (`String`, optional) — `"up"` | `"down"` | `"left"` | `"right"`
    /// - `x` / `y` (`Double`, optional) — screen coordinates
    /// - `attributes` (`[String: Any]`, optional) — custom attributes
    public func setUserInteraction(_ dictionary: [String: Any]) {
        guard CoralogixRum.isInitialized else { return }
        reportHybridUserInteraction(dictionary)
    }
    
    public func sendBeforeSendData(_ data: [[String: Any]]) {
        guard CoralogixRum.isInitialized else { return }
        self.coralogixExporter?.sendBeforeSendData(data: data)
    }
    
    public func sendCustomMeasurement(name: String, value: Double) {
        guard CoralogixRum.isInitialized else { return }
        let span = self.makeSpan(event: .customMeasurement, source: .code, severity: .info)
        span.setAttribute(key: Keys.name.rawValue, value: name)
        span.setAttribute(key: Keys.value.rawValue, value: value)
        span.end()
    }

    /// Returns a tracer for manual custom spans (API naming aligned with the Coralogix Browser SDK: `startCustomSpan`, `endSpan`).
    ///
    /// CX-35956: Returns `nil` when the SDK is not initialized, `traceParentInHeader` is not configured with `enable: true`,
    /// or a custom tracer was already obtained (singleton until `shutdown()`). The issuance check is locked so concurrent calls cannot both obtain a tracer.
    ///
    /// - Parameter ignoredInstruments: When starting a global span via this tracer, listed instruments do not inherit that global trace (CX-35955); auto spans for those types use `setNoParent()`.
    public func getCustomTracer(ignoredInstruments: Set<CoralogixIgnoredInstrument> = []) -> CoralogixCustomTracer? {
        guard CoralogixRum.isInitialized else {
            Log.w("Coralogix RUM is not initialized — getCustomTracer unavailable")
            return nil
        }
        guard let opts = self.options else {
            Log.w("getCustomTracer unavailable — exporter options missing (SDK may not be fully initialized)")
            return nil
        }
        guard let tpDict = opts.traceParentInHeader else {
            Log.w("traceParentInHeader must be enabled to use custom tracer")
            return nil
        }
        let traceParent = TraceParentInHeader(params: tpDict)
        guard traceParent.enable else {
            Log.w("traceParentInHeader must be enabled to use custom tracer")
            return nil
        }
        Self.customTracerIssuanceLock.lock()
        defer { Self.customTracerIssuanceLock.unlock() }
        guard !CoralogixRum.customTracerIssued else {
            Log.w("Custom tracer already exists")
            return nil
        }
        CoralogixRum.customTracerIssued = true
        return CoralogixCustomTracer(rum: self, ignoredInstruments: ignoredInstruments)
    }
    
    // MARK: - Spans & Attributes
    internal var options: CoralogixExporterOptions? { return self.coralogixExporter?.getOptions() }
    
    internal func addUserMetadata(to span: inout any Span) {
        guard let options = self.options else { return }
        span.setAttribute(key: Keys.userId.rawValue, value: options.userContext?.userId ?? "")
        span.setAttribute(key: Keys.userName.rawValue, value: options.userContext?.userName ?? "")
        span.setAttribute(key: Keys.userEmail.rawValue, value: options.userContext?.userEmail ?? "")
        span.setAttribute(key: Keys.environment.rawValue, value: options.environment)
    }

    /// Current and previous session IDs plus user and environment — shared by `makeSpan` and manual custom spans.
    internal func addRumCorrelationMetadata(to span: inout any Span) {
        addSessionAndPrevSessionMetadata(to: &span)
        addUserMetadata(to: &span)
    }

    private func addSessionAndPrevSessionMetadata(to span: inout any Span) {
        if let sessionMetadata = self.coralogixExporter?.getSessionManager().sessionMetadata {
            span.setAttribute(key: Keys.sessionCreationDate.rawValue, value: String(Int(sessionMetadata.sessionCreationDate)))
            span.setAttribute(key: Keys.sessionId.rawValue, value: sessionMetadata.sessionId)
        }
        if let prevSessionMetadata = self.coralogixExporter?.getSessionManager().getPrevSessionMetadata() {
            if let prevPid = prevSessionMetadata.oldPid {
                span.setAttribute(key: Keys.prevPid.rawValue, value: prevPid)
            }
            if let prevSessionId = prevSessionMetadata.oldSessionId {
                span.setAttribute(key: Keys.prevSessionId.rawValue, value: prevSessionId)
            }
            if let prevSessionCreationDate = prevSessionMetadata.oldSessionTimeInterval {
                span.setAttribute(key: Keys.prevSessionCreationDate.rawValue, value: String(Int(prevSessionCreationDate)))
            }
        }
    }
    
    private func displayCoralogixWord() {
        var coralogixText = """
           [CORALOGIX]
           Version: \(Global.sdk.rawValue)
           Swift Version: \(Global.swiftVersion.rawValue)
           Support: iOS, tvOS\n\n
           """
        
        if !CoralogixRum.mobileSDK.sdkFramework.isNative {
            coralogixText += """
               Hybrid Version: \(CoralogixRum.mobileSDK.sdkFramework.version)\n\n
               """
        }
        print(coralogixText)
    }
    
    /// Maps auto-instrumented `CoralogixEventType` values to `CoralogixIgnoredInstrument` (CX-35955).
    private static func ignoredInstrument(forAutoSpanEvent event: CoralogixEventType) -> CoralogixIgnoredInstrument? {
        switch event {
        case .networkRequest: return .networkRequests
        case .userInteraction: return .userInteractions
        case .error: return .errors
        default:
            // Event types without a mapping never use `ignoredInstruments`; they follow the global parent policy in `applyAutoInstrumentationParentPolicy`.
            return nil
        }
    }

    /// CX-35955: opt out of global trace when this event type is in the active global's `ignoredInstruments`.
    /// CX-35954: when a global span is registered, always explicitly set it as parent. The default `.currentSpan`
    /// behavior relies on `os_activity` thread-local context which doesn't propagate reliably across swizzle
    /// boundaries or closures — `activeSpan` is often nil even when a global is active.
    private static func applyAutoInstrumentationParentPolicy(builder: SpanBuilder, event: CoralogixEventType) {
        if let ignored = ignoredInstrument(forAutoSpanEvent: event),
           CoralogixCustomGlobalSpanRegistry.shared.shouldBreakTraceInheritance(for: ignored) {
            _ = builder.setNoParent()
            return
        }
        if let global = CoralogixCustomGlobalSpanRegistry.shared.registeredGlobalForAutoInstrumentationParent() {
            _ = builder.setParent(global)
        }
    }

    internal func makeSpan(event: CoralogixEventType, source: Keys, severity: CoralogixLogSeverity) -> any Span {
        let builder = tracerProvider().spanBuilder(spanName: Keys.iosSdk.rawValue)
        Self.applyAutoInstrumentationParentPolicy(builder: builder, event: event)
        var span = builder.startSpan()
        span.setAttribute(key: Keys.eventType.rawValue, value: event.rawValue)
        span.setAttribute(key: Keys.source.rawValue, value: source.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(severity.rawValue))
        addRumCorrelationMetadata(to: &span)
        return span
    }
}
