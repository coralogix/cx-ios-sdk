/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// OpenTelemetry resource attributes.
/// This is a minimal set containing only the attributes used by the Coralogix SDK.
public enum ResourceAttributes: String {
    case serviceName = "service.name"
    case telemetrySdkName = "telemetry.sdk.name"
    case telemetrySdkLanguage = "telemetry.sdk.language"
    case telemetrySdkVersion = "telemetry.sdk.version"
}
