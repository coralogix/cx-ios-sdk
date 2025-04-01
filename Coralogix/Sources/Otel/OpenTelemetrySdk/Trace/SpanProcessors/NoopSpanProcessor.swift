/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
// 

struct NoopSpanProcessor: SpanProcessor {
    init() {}
    
    let isStartRequired = false
    let isEndRequired = false
    
    func onStart(parentContext: SpanContext?, span: any ReadableSpan) {}
    
    func onEnd(span: any ReadableSpan) {}
    
    func shutdown(explicitTimeout: TimeInterval? = nil) {}
    
    func forceFlush(timeout: TimeInterval? = nil) {}
}
