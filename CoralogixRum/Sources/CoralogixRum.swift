import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import URLSessionInstrumentation
import Darwin
import UIKit

public class CoralogixRum {
    internal var coralogixExporter: CoralogixExporter
    internal var versionMetadata: VersionMetadata
    internal var sessionInstrumentation: URLSessionInstrumentation?
    internal var networkManager = NetworkManager()
    let notificationCenter = NotificationCenter.default

    static var isDebug = false
    static var isInitialized = false

    public init(options: CoralogixExporterOptions) {
        if CoralogixRum.isInitialized { 
            Log.w("CoralogixRum allready Initialized")
        }

        self.versionMetadata = VersionMetadata(appName: options.application, appVersion: options.version)
        CoralogixRum.isDebug = options.debug
        self.coralogixExporter = CoralogixExporter(options: options,
                                                   versionMetadata: self.versionMetadata, 
                                                   sessionManager: SessionManager(),
                                                   networkManager: self.networkManager)
        OpenTelemetry.registerTracerProvider(tracerProvider: TracerProviderBuilder()
            .add(spanProcessor: BatchSpanProcessor(spanExporter: self.coralogixExporter,
                                                   scheduleDelay: Double(Global.BatchSpan.scheduleDelay.rawValue),
                                                   maxExportBatchSize: Global.BatchSpan.maxExportBatchSize.rawValue))
                .build())
        self.initializeViewInstrumentation()
        self.initializeCrashInstumentation()
        self.initializeSessionInstrumentation()

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

public struct CXView {
    enum AppState: String {
        case notifyOnAppear
        case notifyOnDisappear
    }
    
    let state: AppState
    let name: String
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
