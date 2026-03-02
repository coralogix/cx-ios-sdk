//
//  CoralogixExporterOptions.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 24/06/2025.
//

import Foundation

public struct CoralogixExporterOptions {
    
    public enum MobileVitalsType: String {
        case warmDetector
        case coldDetector
        case cpuDetector
        case memoryDetector
        case renderingDetector
        case slowFrozenFramesDetector
    }
    
    public enum InstrumentationType: String {
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
    
    /// A list of instruments that you wish to switch off during runtime. all instrumentations are active by default.
    var instrumentations: [InstrumentationType: Bool]?
    
    /// Determines whether the SDK should collect the user's IP address and corresponding geolocation data. Defaults to true.
    var collectIPData: Bool
    
    /// Enable event access and modification before sending to Coralogix, supporting content modification, and event discarding.
    var beforeSend: (([String: Any]) -> [String: Any]?)?
    
    /// Alternative beforeSend for Other Platfoms.
    public var beforeSendCallBack: (([[String: Any]]) -> Void)?
    
    /// When set to `false`, disables Coralogix's automatic method swizzling.
    ///
    /// Swizzling is used to auto-instrument various system behaviors (e.g., view controller lifecycle,
    /// app delegate events, network calls). Disabling it gives you full manual control over instrumentation.
    ///
    /// - Remark: As of the current Coralogix SDK version, `enableSwizzling = false` only disables `NSURLSession` instrumentation.
    public var enableSwizzling: Bool
    
    public var proxyUrl: String?
    
    public var traceParentInHeader: [String: Any]?
    
    /// A list of mobile vitals that you wish to switch off during runtime. all mobile vitals are active by default.
    var mobileVitals: [MobileVitalsType: Bool]?

    /// Per-URL rules for capturing request/response headers and payloads.
    /// `nil` (default) disables all header and payload capture.
    public var networkExtraConfig: [NetworkCaptureRule]?

    public init(coralogixDomain: CoralogixDomain,
                userContext: UserContext? = nil,
                environment: String,
                application: String,
                version: String,
                publicKey: String,
                ignoreUrls: [String]? = nil,
                ignoreErrors: [String]? = nil,
                labels: [String: Any]? = nil,
                sessionSampleRate: Int = 100, // percent (0–100)
                instrumentations: [InstrumentationType: Bool]? = nil,
                collectIPData: Bool = true,
                beforeSend: (([String: Any]) -> [String: Any]?)? = nil,
                enableSwizzling: Bool = true,
                proxyUrl: String? = nil,
                traceParentInHeader: [String: Any]? = nil,
                mobileVitals: [MobileVitalsType: Bool]? = nil,
                networkExtraConfig: [NetworkCaptureRule]? = nil,
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
        self.sdkSampler = SDKSampler(sampleRate: sessionSampleRate)
        self.instrumentations = instrumentations
        self.collectIPData = collectIPData
        self.beforeSend = beforeSend
        self.enableSwizzling = enableSwizzling
        self.proxyUrl = proxyUrl
        self.traceParentInHeader = traceParentInHeader
        self.mobileVitals = mobileVitals
        self.networkExtraConfig = networkExtraConfig
    }
    
    internal func shouldInitInstrumentation(instrumentation: InstrumentationType) -> Bool {
        return self.instrumentations?[instrumentation] ?? true
    }
    
    internal func shouldInitMobileVitals(mobileVital: MobileVitalsType) -> Bool {
        return self.mobileVitals?[mobileVital] ?? true
    }
    
    internal func getInitData() -> [String: Any] {
        var initData: [String: Any] = [:]
        initData[Keys.userContext.rawValue] = self.userContext?.getDictionary()
        initData[Keys.environment.rawValue] = self.environment
        initData[Keys.application.rawValue] = self.application
        initData[Keys.version.rawValue] = self.version
        initData[Keys.ignoreUrls.rawValue] = self.ignoreUrls
        initData[Keys.ignoreErrors.rawValue] = self.ignoreErrors
        initData[Keys.labels.rawValue] = self.labels
        initData[Keys.sessionSampleRate.rawValue] = self.sdkSampler.sampleRate
        initData[Keys.instrumentations.rawValue] = self.getStatesAsDictionary(from: self.instrumentations)
        initData[Keys.collectIPData.rawValue] = self.collectIPData
        initData[Keys.enableSwizzling.rawValue] = self.enableSwizzling
        initData[Keys.proxyUrl.rawValue] = self.proxyUrl
        initData[Keys.traceParentInHeader.rawValue] = self.traceParentInHeader
        initData[Keys.mobileVitals.rawValue] = self.getStatesAsDictionary(from: self.mobileVitals)
        initData[Keys.debug.rawValue] = self.debug
        
        if self.beforeSend != nil {
            initData[Keys.beforeSend.rawValue] = Keys.exists.rawValue
        }
        return initData
    }
    
    private func getStatesAsDictionary<Key: RawRepresentable>(
        from items: [Key: Bool]?
    ) -> [String: Bool] where Key.RawValue == String {
        guard let items else { return [:] }

        return items.reduce(into: [String: Bool]()) { acc, pair in
            acc[pair.key.rawValue] = pair.value
        }
    }
}
