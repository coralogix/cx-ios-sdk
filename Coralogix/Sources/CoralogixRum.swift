import Foundation
import Darwin
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

    internal var tracerProvider: () -> Tracer = {
        return OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: Keys.iosSdk.rawValue,
            instrumentationVersion: Global.sdk.rawValue
        )
    }
    
    let notificationCenter = NotificationCenter.default
    
    static var isInitialized = false
    static var mobileSDK: MobileSDK = MobileSDK()
    
    public init(options: CoralogixExporterOptions,
                sdkFramework: SdkFramework = .swift,
                sessionManager: SessionManager? = SessionManager()) {
        Log.isDebug = options.debug
        self.sessionManager = sessionManager
        self.displayCoralogixWord()

        if options.sdkSampler.shouldInitialized() == false {
            Log.e("Initialization skipped due to sample rate.")
            return
        }
        
        CoralogixRum.mobileSDK = MobileSDK(sdkFramework: sdkFramework)
        self.startup(options: options)
    }
    
    deinit {
        // Remove observer to avoid memory leaks
        NotificationCenter.default.removeObserver(self, name: .cxRumNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: .cxRumNotificationUserActions, object: nil)
        NotificationCenter.default.removeObserver(self, name: .cxRumNotificationSessionEnded, object: nil)
        NotificationCenter.default.removeObserver(self, name: .cxRumNotificationMetrics, object: nil)
        NotificationCenter.default.removeObserver(self, name: .cxViewDidAppear, object: nil)
        self.removeLifeCycleNotification()
    }
    
    private func removeLifeCycleNotification() {
        NotificationCenter.default.removeObserver(self,
                                            name: UIApplication.didFinishLaunchingNotification,
                                            object: nil)
        NotificationCenter.default.removeObserver(self,
                                            name: UIApplication.didBecomeActiveNotification,
                                            object: nil)
        NotificationCenter.default.removeObserver(self,
                                            name: UIApplication.didEnterBackgroundNotification,
                                            object: nil)
        NotificationCenter.default.removeObserver(self,
                                            name: UIApplication.willTerminateNotification,
                                            object: nil)
        NotificationCenter.default.removeObserver(self,
                                            name: UIApplication.didReceiveMemoryWarningNotification,
                                            object: nil)
    }
    
    private func startup(options: CoralogixExporterOptions) {
        guard let sessionManager = self.sessionManager else {
            Log.e("SessionManager is nil.")
            return
        }
        
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
            (.errors, self.initializeCrashInstumentation),
            (.mobileVitals, self.initializeMobileVitalsInstrumentation),
            (.anr, self.initializeMobileVitalsInstrumentation)
        ]

        for (type, initializer) in instrumentationMap
            where options.shouldInitInstrumentation(instrumentation: type) {
            initializer()
        }
    }
    
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

    private func initialzeMetricsManager(options: CoralogixExporterOptions) {
        self.metricsManager.addObservers()

        if options.shouldInitInstrumentation(instrumentation: .mobileVitals) {
            self.metricsManager.startFPSSamplingMonitoring(mobileVitalsFPSSamplingRate: options.mobileVitalsFPSSamplingRate)
            self.metricsManager.startColdStartMonitoring()
            self.metricsManager.startCPUMonitoring()
            self.metricsManager.startMemoryMonitoring()
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
        self.initialzeMetricsManager(options: options)
        self.initializeNavigationInstrumentation()
    }
    
    private func swizzle() {
        UIApplication.swizzleTouchesEnded
        UIViewController.swizzleViewDidAppear
        UIViewController.swizzleViewDidDisappear
        UIApplication.swizzleSendEvent
    }
    
    public func setUserContext(userContext: UserContext) {
        if CoralogixRum.isInitialized {
            self.coralogixExporter?.updade(userContext: userContext)
        }
    }
    
    public func getUserContext() -> UserContext? {
        if CoralogixRum.isInitialized {
            return self.coralogixExporter?.getOptions().userContext
        }
        return nil
    }
    
    public func setLabels(labels: [String: Any]) {
        if CoralogixRum.isInitialized {
            self.coralogixExporter?.updade(labels: labels)
        }
    }
    
    public func getLabels() -> [String: Any]? {
        return self.coralogixExporter?.getOptions().labels
    }
    
    public func reportError(exception: NSException) {
        if CoralogixRum.isInitialized {
            self.reportErrorWith(exception: exception)
        }
    }
    
    public func reportError(error: NSError) {
        if CoralogixRum.isInitialized {
            self.reportErrorWith(error: error)
        }
    }
    
    public func reportError(error: Error) {
        if CoralogixRum.isInitialized {
            self.reportErrorWith(error: error)
        }
    }
    
    public func setView(name: String) {
        if CoralogixRum.isInitialized {
            let cxView = CXView(state: .notifyOnAppear, name: name)
            self.coralogixExporter?.set(cxView: cxView)
        }
    }
    
    public func reportError(message: String, data: [String: Any]?) {
        if CoralogixRum.isInitialized {
            self.reportErrorWith(message: message, data: data)
        }
    }
    
    // Depractead
    public func reportError(message: String, stackTrace: String?) {
        if CoralogixRum.isInitialized {
            self.reportErrorWith(message: message, stackTrace: stackTrace)
        }
    }
    
    public func reportError(message: String, stackTrace: [[String: Any]], errorType: String?) {
        if CoralogixRum.isInitialized {
            self.reportErrorWith(message: message, stackTrace: stackTrace, errorType: errorType)
        }
    }
    
    public func log(severity: CoralogixLogSeverity,
                    message: String,
                    data: [String: Any]? = nil) {
        if CoralogixRum.isInitialized {
            self.logWith(severity: severity, message: message, data: data)
        }
    }
    
    public func shutdown() {
        CoralogixRum.isInitialized = false
        self.coralogixExporter?.shutdown(explicitTimeout: nil)
        self.metricsManager.removeObservers()
    }
    
    public func isInitialized() -> Bool {
        return CoralogixRum.isInitialized
    }

    public func getSessionId() -> String? {
        return self.sessionManager?.getSessionMetadata()?.sessionId
    }
    
    public func setApplicationContext(application: String, version: String) {
        self.coralogixExporter?.updade(application: application, version: version)
    }
    
    public func sendBeforeSendData(data: [[String: Any]]) {
        self.coralogixExporter?.sendBeforeSendData(data: data)
    }
    
    public func recordFirstFrameTime(params: [String: Any]) {
        if let cxMobileVitals = self.metricsManager.getCXMobileVitals(params: params) {
            NotificationCenter.default.post(name: .cxRumNotificationMetrics, object: cxMobileVitals)
        }
    }
    
    internal func addUserMetadata(to span: inout any Span) {
        let options = self.coralogixExporter?.getOptions()
        span.setAttribute(key: Keys.userId.rawValue, value: options?.userContext?.userId ?? "")
        span.setAttribute(key: Keys.userName.rawValue, value: options?.userContext?.userName ?? "")
        span.setAttribute(key: Keys.userEmail.rawValue, value: options?.userContext?.userEmail ?? "")
        span.setAttribute(key: Keys.environment.rawValue, value: options?.environment ?? "")
    }
    
    func displayCoralogixWord() {
        let coralogixText = "[CORALOGIX]\nVerion: \(Global.sdk.rawValue) \nSwift Verion: \(Global.swiftVersion.rawValue) \nSupport iOS, tvOS\n\n\n"
        print(coralogixText)
    }
}
