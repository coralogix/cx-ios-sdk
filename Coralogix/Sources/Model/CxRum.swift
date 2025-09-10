//
//  CxRum.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation
import CoralogixInternal

struct CxRum {
    let timeStamp: TimeInterval
    let networkRequestContext: NetworkRequestContext
    let versionMetadata: VersionMetadata
    let sessionContext: SessionContext?
    let prevSessionContext: SessionContext?
    let eventContext: EventContext
    let logContext: LogContext
    let mobileSDK: MobileSDK
    let environment: String
    let traceId: String
    let spanId: String
    let errorContext: ErrorContext
    let deviceContext: DeviceContext
    let deviceState: DeviceState
    let labels: [String: Any]?
    let snapshotContext: SnapshotContext?
    let interactionContext: InteractionContext?
    let mobileVitalsContext: MobileVitalsContext?
    let lifeCycleContext: LifeCycleContext?
    let screenShotContext: ScreenshotContext?
    let internalContext: InternalContext?
    let fingerPrint: String
}
