//
//  CoralogixExporterOptions.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 24/06/2025.
//

import Foundation

public struct CoralogixExporterOptions {
    
    public enum InstrumentationType {
        case mobileVitals
        case custom
        case errors
        case network
        case userActions
        case anr
        case lifeCycle
    }

    /// Configuration for user context.
    var userContext: UserContext?
    
    /// Turns on/off internal debug logging
    let debug: Bool
    
    /// Applies for Fetch URLs. URLs that match that regex will not be traced.
    let ignoreUrls: [String]?
    
    /// A pattern for error messages which should not be sent to Coralogix. By default, all errors will be sent.
    let ignoreErrors: [String]?
    
    /// Coralogix account domain
    let coralogixDomain: CoralogixDomain
    
    /// Coralogix token
    var publicKey: String
    
    /// Environment
    let environment: String
    
    /// Application name
    var application: String
    
    /// Appliaction version
    var version: String
        
    var labels: [String: Any]?
    
    /// Number between 0-100 as a precentage of SDK should be init.
    var sdkSampler: SDKSampler
    
    /// The timeinterval the SDK will run the FPS sampling in an hour. default is every 1 minute.
    let mobileVitalsFPSSamplingRate: Int
    
    /// A list of instruments that you wish to switch off during runtime. all instrumentations are active by default.
    var instrumentations: [InstrumentationType: Bool]?
    
    /// Determines whether the SDK should collect the user's IP address and corresponding geolocation data. Defaults to true.
    var collectIPData: Bool
    
    /// Enable event access and modification before sending to Coralogix, supporting content modification, and event discarding.
    var beforeSend: (([String: Any]) -> [String: Any]?)?
    
    /// Alternative beforeSend for Other Platfoms.
    public var beforeSendCallBack: (([[String: Any]]) -> Void)? = nil
    
    /// When set to `false`, disables Coralogix's automatic method swizzling.
    ///
    /// Swizzling is used to auto-instrument various system behaviors (e.g., view controller lifecycle,
    /// app delegate events, network calls). Disabling it gives you full manual control over instrumentation.
    ///
    /// - Remark: As of the current Coralogix SDK version, `enableSwizzling = false` only disables `NSURLSession` instrumentation.
    public var enableSwizzling: Bool
    
    public var proxyUrl: String?
    
    public var traceParentInHeader: [String: Any]?
    
    /// The Array of Prefixes you can avoid in swizzle process (Network)
    public let ignoredClassPrefixes: [String]?
    
    public init(coralogixDomain: CoralogixDomain,
                userContext: UserContext? = nil,
                environment: String,
                application: String,
                version: String,
                publicKey: String,
                ignoreUrls: [String]? = nil,
                ignoreErrors: [String]? = nil,
                labels: [String: Any]? = nil,
                sampleRate: Int = 100,
                mobileVitalsFPSSamplingRate: Int = 300, // minimum every 5 minute
                instrumentations: [InstrumentationType: Bool]? = nil,
                collectIPData: Bool = true,
                beforeSend: (([String: Any]) -> [String: Any]?)? = nil,
                enableSwizzling: Bool = true,
                proxyUrl: String? = nil,
                traceParentInHeader: [String: Any]? = nil,
                ignoredClassPrefixes: [String]? = nil,
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
        self.labels = labels
        self.sdkSampler = SDKSampler(sampleRate: sampleRate)
        self.mobileVitalsFPSSamplingRate = mobileVitalsFPSSamplingRate
        self.instrumentations = instrumentations
        self.collectIPData = collectIPData
        self.beforeSend = beforeSend
        self.enableSwizzling = enableSwizzling
        self.proxyUrl = proxyUrl
        self.traceParentInHeader = traceParentInHeader
        self.ignoredClassPrefixes = ignoredClassPrefixes
    }
    
    internal func shouldInitInstrumentation(instrumentation: InstrumentationType) -> Bool {
        if let keys = self.instrumentations?.keys {
            if keys.contains(instrumentation) {
                return self.instrumentations?[instrumentation] ?? true
            }
        }
        return true
    }
}
