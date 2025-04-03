//
// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
// 

import Foundation

public class LoggerProviderSdk : LoggerProvider {
    private var sharedState: LoggerSharedState
    private var loggerRegistry : ComponentRegistry<LoggerSdk>
    public init(clock: Clock = MillisClock(),
                resource: Resource = EnvVarResource.get(),
                logLimits: LogLimits = LogLimits(),
                logRecordProcessors: [LogRecordProcessor] = []) {
        sharedState = LoggerSharedState(resource: resource,
                                        logLimits: logLimits,
                                        processors: logRecordProcessors,
                                        clock: clock)
      
        loggerRegistry = ComponentRegistry<LoggerSdk> { [sharedState] scope in
            return LoggerSdk(sharedState: sharedState, instrumentationScope: scope, eventDomain: nil)
            
        }
    }
    
    public func get(instrumentationScopeName: String) -> Logger {
        return loggerRegistry.get(name: instrumentationScopeName, version: nil, schemaUrl: nil)
    }
    
    public func loggerBuilder(instrumentationScopeName: String) -> LoggerBuilder {
        return LoggerBuilderSdk(registry: loggerRegistry, instrumentationScopeName: instrumentationScopeName)
    }
}
