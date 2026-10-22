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
    // The one-shot setUserContext token this event's snapshot promotion consumed, if
    // any — the beforeSend drop path in CxSpan.getDictionary() hands it back (re-arms)
    // so the next accepted event still carries the promotion.
    var consumedSnapshotTrigger: PendingSnapshotTrigger? = nil
    // Whether the event belongs to the live session, decided once at build so the
    // beforeSend error-count compensation in CxSpan.getDictionary() adjusts the same
    // counters the build counted the event on.
    var isLiveSession: Bool = true
    let interactionContext: InteractionContext?
    let mobileVitalsContext: MobileVitalsContext?
    let lifeCycleContext: LifeCycleContext?
    let screenShotContext: ScreenshotContext?
    let internalContext: InternalContext?
    let measurementContext: MeasurementContext?
    let fingerPrint: String
    // CX-44687: product-analytics fields at cx_rum top level.
    // `isNavigationEvent` is always emitted; `viewNumber` is nil until the first
    // view appears (early-launch spans omit it).
    let isNavigationEvent: Bool
    let viewNumber: Int?
    // View frozen at span creation; nil → CxRumPayloadBuilder falls back to the live ViewManager.
    let viewName: String?
}
