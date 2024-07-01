import Foundation
import Darwin
import UIKit

extension Notification.Name {
    static let cxRumNotification = Notification.Name("cxRumNotification")
    static let cxRumNotificationSessionEnded = Notification.Name("cxRumNotificationSessionEnded")
}

public class CoralogixRum {
    internal var coralogixExporter: CoralogixExporter
    internal var versionMetadata: VersionMetadata
    internal var networkManager = NetworkManager()
    internal var viewManager = ViewManager(keyChain: KeychainManager())
    internal var sessionManager = SessionManager()
    internal var sessionInstrumentation: URLSessionInstrumentation?
    let notificationCenter = NotificationCenter.default

    static var isDebug = false
    static var isInitialized = false
    static var sdkFramework: SdkFramework = .swift

    public init(options: CoralogixExporterOptions, sdkFramework: SdkFramework = .swift) {
        if CoralogixRum.isInitialized {
            Log.w("CoralogixRum allready Initialized")
        }
        CoralogixRum.sdkFramework = sdkFramework
        self.versionMetadata = VersionMetadata(appName: options.application, appVersion: options.version)
        CoralogixRum.isDebug = options.debug
        self.coralogixExporter = CoralogixExporter(options: options,
                                                   versionMetadata: self.versionMetadata, 
                                                   sessionManager: self.sessionManager,
                                                   networkManager: self.networkManager,
                                                   viewManager: self.viewManager)
        
        OpenTelemetry.registerTracerProvider(tracerProvider: TracerProviderBuilder()
            .add(spanProcessor: BatchSpanProcessor(spanExporter: self.coralogixExporter,
                                                   scheduleDelay: Double(Global.BatchSpan.scheduleDelay.rawValue),
                                                   maxExportBatchSize: Global.BatchSpan.maxExportBatchSize.rawValue))
                .build())
        self.initializeNavigationInstrumentation()
        self.initializeSessionInstrumentation()
        self.initializeCrashInstumentation()

        CoralogixRum.isInitialized = true
    }
    
    deinit {
        // Remove observer to avoid memory leaks
        NotificationCenter.default.removeObserver(self, name: .cxRumNotification, object: nil)
    }
    
    public func setUserContext(userContext: UserContext) {
        self.coralogixExporter.updade(userContext: userContext)
    }
    
    public func setLabels(labels: [String: Any]) {
        self.coralogixExporter.updade(labels: labels)
    }
    
    public func reportError(exception: NSException) {
        self.reportErrorWith(exception: exception)
    }
    
    public func reportError(error: NSError) {
        self.reportErrorWith(error: error)
    }
    
    public func reportError(error: Error) {
        self.reportErrorWith(error: error)
    }
    
    public func reportError(message: String, data: [String: Any]?) {
        self.reportErrorWith(message: message, data: data)
    }
    
    public func log(severity: CoralogixLogSeverity, message: String, data: [String: Any]?) {
        self.logWith(severity: severity, message: message, data: data)
    }
    
    public func shutdown() {
        CoralogixRum.isInitialized = false
        self.coralogixExporter.shutdown()
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
    }
}
