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

    internal lazy var tracerProvider: () -> Tracer = {
        return OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: Keys.iosSdk.rawValue,
            instrumentationVersion: Global.sdk.rawValue
        )
    }
    
    static var isInitialized = false
    static var mobileSDK: MobileSDK = MobileSDK()
    
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
        
        for (type, initializer) in instrumentationMap where options.shouldInitInstrumentation(instrumentation: type) {
            initializer()
        }
    }
    
    // MARK: - Tracing
    internal func setupTracer(applicationName: String) {
        guard let exporter = self.coralogixExporter else {
            Log.e("Failed to setup tracer: coralogixExporter is nil")
            return
        }
        
        let resource = Resource(attributes: [
            ResourceAttributes.serviceName.rawValue: .string(applicationName)
        ])
        
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
        UIApplication.swizzleTouchesEnded
        UIViewController.swizzleViewDidAppear
        UIViewController.swizzleViewDidDisappear
        UIApplication.swizzleSendEvent
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
                            isCrash: Bool = false) {
        guard CoralogixRum.isInitialized else { return }
        self.reportErrorWith(message: message,
                             stackTrace: stackTrace,
                             errorType: errorType,
                             isCrash: isCrash)
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
        CoralogixRum.isInitialized = false
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
    
    // MARK: - Spans & Attributes
    internal var options: CoralogixExporterOptions? { return self.coralogixExporter?.getOptions() }
    
    internal func addUserMetadata(to span: inout any Span) {
        guard let options = self.options else { return }
        span.setAttribute(key: Keys.userId.rawValue, value: options.userContext?.userId ?? "")
        span.setAttribute(key: Keys.userName.rawValue, value: options.userContext?.userName ?? "")
        span.setAttribute(key: Keys.userEmail.rawValue, value: options.userContext?.userEmail ?? "")
        span.setAttribute(key: Keys.environment.rawValue, value: options.environment)
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
    
    internal func makeSpan(event: CoralogixEventType, source: Keys, severity: CoralogixLogSeverity) -> any Span {
        var span = tracerProvider().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        span.setAttribute(key: Keys.eventType.rawValue, value: event.rawValue)
        span.setAttribute(key: Keys.source.rawValue, value: source.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(severity.rawValue))
        
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
        
        self.addUserMetadata(to: &span)
        return span
    }
}
