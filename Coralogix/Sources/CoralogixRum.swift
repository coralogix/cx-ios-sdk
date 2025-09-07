import Foundation
@_exported import CoralogixInternal

#if canImport(UIKit)
import UIKit
#endif

extension Notification.Name {
    static let cxRumNotification = Notification.Name("cxRumNotification")
    static let cxRumNotificationSessionEnded = Notification.Name("cxRumNotificationSessionEnded")
    static let cxRumNotificationUserActions = Notification.Name("cxRumNotificationUserActions")
    static let cxRumNotificationMetrics = Notification.Name("cxRumNotificationMetrics")
    static let cxViewDidAppear = Notification.Name("cxViewDidAppear")
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
    var mobileVitalHandlers: ((MobileVitals) -> Void)?

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
        NotificationCenter.default.removeObserver(self, name: .cxRumNotificationSessionEnded, object: nil)
        NotificationCenter.default.removeObserver(self, name: .cxRumNotificationMetrics, object: nil)
        NotificationCenter.default.removeObserver(self, name: .cxViewDidAppear, object: nil)
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
        
        self.setupCoreModules(options: options)
        self.setupExporter(sessionManager: sessionManager, options: options)
        self.setupTracer(applicationName: options.application)
        self.swizzle()
        self.initializeEnabledInstrumentations(using: options)
        CoralogixRum.isInitialized = true
    }
    
    private func initializeEnabledInstrumentations(using options: CoralogixExporterOptions) {
        let instrumentationMap: [(CoralogixExporterOptions.InstrumentationType, () -> Void)] = [
            (.lifeCycle, self.initializeLifeCycleInstrumentation),
            (.userActions, self.initializeUserActionsInstrumentation),
            (.network, self.initializeNetworkInstrumentation),
            (.errors, self.initializeCrashInstrumentation),
            (.mobileVitals, self.initializeMobileVitalsInstrumentation),
            (.anr, self.initializeMobileVitalsInstrumentation)
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
    
    private func initializeMetricsManager(options: CoralogixExporterOptions) {
        self.metricsManager.addObservers()
        
        if options.shouldInitInstrumentation(instrumentation: .mobileVitals) {
            self.metricsManager.startFPSSamplingMonitoring(mobileVitalsFPSSamplingRate: options.mobileVitalsFPSSamplingRate)
            self.metricsManager.startColdStartMonitoring()
            self.metricsManager.startCPUMonitoring()
            self.metricsManager.startMemoryMonitoring()
            self.metricsManager.startSlowFrozenFramesMonitoring()
        }
        
        if options.shouldInitInstrumentation(instrumentation: .anr) {
            self.metricsManager.startANRMonitoring()
        }
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
    
    private func setupCoreModules(options: CoralogixExporterOptions) {
        self.initializeSessionReplay()
        self.initializeMetricsManager(options: options)
        self.initializeNavigationInstrumentation()
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
    
    public func setUserContext(userContext: UserContext) {
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
    
    @available(*, deprecated, message: "Currently use for Flutter only, will be removed in future")
    public func reportError(message: String, stackTrace: String?) {
        guard CoralogixRum.isInitialized else { return }
        self.reportErrorWith(message: message, stackTrace: stackTrace)
    }
    
    public func reportError(message: String, stackTrace: [[String: Any]], errorType: String?) {
        guard CoralogixRum.isInitialized else { return }
        self.reportErrorWith(message: message, stackTrace: stackTrace, errorType: errorType)
    }
    
    public func reportMobileVitalsMeasurement(type: String, metrics: [HybridMetric]) {
        guard CoralogixRum.isInitialized else { return }
        if (CoralogixRum.mobileSDK.sdkFramework.isNative) { return }
        
        let uuid = UUID().uuidString.lowercased()
        metrics.forEach { element in
            let mobileVitals = MobileVitals(
                type: MobileVitalsType(from: type),
                name: element.name,
                value: element.value,
                units: MeasurementUnits(from: element.units),
                uuid: uuid
            )
            self.handleMobileVitals(mobileVitals)
        }
    }
    
    public func reportMobileVitalsMeasurement(type: String, value: Double, units: String) {
        guard CoralogixRum.isInitialized else { return }
        if (CoralogixRum.mobileSDK.sdkFramework.isNative) { return }
        
        let mobileVitals = MobileVitals(
            type: MobileVitalsType(from: type),
            name: type,
            value: value,
            units: MeasurementUnits(from: units)
        )
        self.handleMobileVitals(mobileVitals)
    }
    
    public func setView(name: String) {
        guard CoralogixRum.isInitialized else { return }
        let cxView = CXView(state: .notifyOnAppear, name: name)
        self.coralogixExporter?.set(cxView: cxView)
    }
    
    public func log(severity: CoralogixLogSeverity, message: String, data: [String: Any]? = nil) {
        guard CoralogixRum.isInitialized else { return }
        self.logWith(severity: severity, message: message, data: data)
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
}
