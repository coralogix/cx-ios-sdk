import Foundation
import Darwin
#if canImport(UIKit)
import UIKit
#endif

extension Notification.Name {
    static let cxRumNotification = Notification.Name("cxRumNotification")
    static let cxRumNotificationSessionEnded = Notification.Name("cxRumNotificationSessionEnded")
    static let cxRumNotificationUserActions = Notification.Name("cxRumNotificationUserActions")
    static let cxRumNotificationMetrics = Notification.Name("cxRumNotificationMetrics")
}

public class CoralogixRum {
    internal var coralogixExporter: CoralogixExporter?
    internal var versionMetadata: VersionMetadata?
    internal var networkManager = NetworkManager()
    internal var viewManager = ViewManager(keyChain: KeychainManager())
    internal var sessionManager = SessionManager()
    internal var sessionInstrumentation: URLSessionInstrumentation?
    internal var metricsManager = MetricsManager()

    let notificationCenter = NotificationCenter.default
    
    static var isDebug = false
    static var isInitialized = false
    static var sdkFramework: SdkFramework = .swift
    
    public init(options: CoralogixExporterOptions, sdkFramework: SdkFramework = .swift) {
        self.displayCoralogixWord()

        if options.sdkSampler.shouldInitialized() == false {
            return
        }
        
        self.startup(options: options, sdkFramework: sdkFramework)
    }
    
    deinit {
        // Remove observer to avoid memory leaks
        NotificationCenter.default.removeObserver(self, name: .cxRumNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: .cxRumNotificationUserActions, object: nil)
        NotificationCenter.default.removeObserver(self, name: .cxRumNotificationSessionEnded, object: nil)
        NotificationCenter.default.removeObserver(self, name: .cxRumNotificationMetrics, object: nil)
    }
    
    private func startup(options: CoralogixExporterOptions, sdkFramework: SdkFramework) {
        CoralogixRum.sdkFramework = sdkFramework
        self.initialzeMetricPerformance(options: options)

        CoralogixRum.isDebug = options.debug
        let versionMetadata = VersionMetadata(appName: options.application, appVersion: options.version)
        let coralogixExporter = CoralogixExporter(options: options,
                                                  versionMetadata: versionMetadata,
                                                  sessionManager: self.sessionManager,
                                                  networkManager: self.networkManager,
                                                  viewManager: self.viewManager,
                                                  metricsManager: self.metricsManager)
        self.versionMetadata = versionMetadata
        self.coralogixExporter = coralogixExporter
        
        let resource = Resource(attributes: [
            ResourceAttributes.serviceName.rawValue: AttributeValue.string(options.application)
        ])
        
        OpenTelemetry.registerTracerProvider(tracerProvider: TracerProviderBuilder().with(resource: resource)
            .add(spanProcessor: BatchSpanProcessor(spanExporter: coralogixExporter,
                                                   scheduleDelay: Double(Global.BatchSpan.scheduleDelay.rawValue),
                                                   maxExportBatchSize: Global.BatchSpan.maxExportBatchSize.rawValue))
                .build())
        
        self.swizzle()
        self.initializeUserActionsInstrumentation()
        self.initializeNavigationInstrumentation()
        self.initializeSessionInstrumentation()
        self.initializeCrashInstumentation()
        self.initializeMobileVitalsInstrumentation()
        self.initializeErrorInstrumentation()

        CoralogixRum.isInitialized = true
    }
    
    private func initialzeMetricPerformance(options: CoralogixExporterOptions) {
        self.metricsManager.startFPSSamplingMonitoring(mobileVitalsFPSSamplingRate: options.mobileVitalsFPSSamplingRate)
        self.metricsManager.startColdStartMonitoring()
        self.metricsManager.startANRMonitoring()
    }
    
    private func swizzle() {
        UIApplication.swizzleTouchesEnded
        UIApplication.swizzleSendAction
        UIViewController.swizzleViewDidAppear
        UIViewController.swizzleViewDidDisappear
        UITableView.swizzleUITableViewDelegate
        UITableViewController.swizzleUITableViewControllerDelegate
        UICollectionView.swizzleUICollectionViewDelegate
        UIPageControl.swizzleSetCurrentPage
    }
    
    public func setUserContext(userContext: UserContext) {
        if CoralogixRum.isInitialized {
            self.coralogixExporter?.updade(userContext: userContext)
        }
    }
    
    public func setLabels(labels: [String: Any]) {
        if CoralogixRum.isInitialized {
            self.coralogixExporter?.updade(labels: labels)
        }
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
        let cxView = CXView(state: .notifyOnAppear, name: name)
        self.coralogixExporter?.set(cxView: cxView)
    }
    
    public func reportError(message: String, data: [String: Any]?) {
        if CoralogixRum.isInitialized {
            self.reportErrorWith(message: message, data: data)
        }
    }
    
    public func reportError(message: String, stackTrace: String?) {
        if CoralogixRum.isInitialized {
            self.reportErrorWith(message: message, stackTrace: stackTrace)
        }
    }
    
    public func log(severity: CoralogixLogSeverity,
                    message: String,
                    data: [String: Any]?) {
        if CoralogixRum.isInitialized {
            self.logWith(severity: severity, message: message, data: data)
        }
    }
    
    public func shutdown() {
        CoralogixRum.isInitialized = false
        self.coralogixExporter?.shutdown()
    }
    
    internal func addUserMetadata(to span: inout Span) {
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

public enum SdkFramework: String {
    case swift
    case flutter
}

public struct CoralogixExporterOptions {
    // Configuration for user context.
    var userContext: UserContext?
    
    // Turns on/off internal debug logging
    let debug: Bool
    
    // Applies for Fetch URLs. URLs that match that regex will not be traced.
    let ignoreUrls: [String]?
    
    // A pattern for error messages which should not be sent to Coralogix. By default, all errors will be sent.
    let ignoreErrors: [String]?
    
    // Coralogix account domain
    let coralogixDomain: CoralogixDomain
    
    // Coralogix token
    var publicKey: String
    
    // Environment
    let environment: String
    
    // Application name
    let application: String
    
    // Appliaction version
    let version: String
    
    let customDomainUrl: String?
    
    var labels: [String: Any]?
    
    var sdkSampler: SDKSampler
    
    let mobileVitalsFPSSamplingRate: Int
    
    public init(coralogixDomain: CoralogixDomain,
                userContext: UserContext?,
                environment: String,
                application: String,
                version: String,
                publicKey: String,
                ignoreUrls: [String]? = nil,
                ignoreErrors: [String]? = nil,
                customDomainUrl: String? = nil,
                labels: [String: Any]? = nil,
                sampleRate: Int = 100,
                mobileVitalsFPSSamplingRate: Int = 300, // minimum every 5 minute
                debug: Bool = false) {
        
        self.coralogixDomain = coralogixDomain
        self.userContext = userContext
        self.publicKey = publicKey
        self.ignoreUrls = ignoreUrls
        self.ignoreErrors = ignoreErrors
        self.debug = debug
        self.environment = environment
        self.application = application
        self.version = version
        self.customDomainUrl = customDomainUrl
        self.labels = labels
        self.sdkSampler = SDKSampler(sampleRate: sampleRate)
        self.mobileVitalsFPSSamplingRate = mobileVitalsFPSSamplingRate
    }
}
