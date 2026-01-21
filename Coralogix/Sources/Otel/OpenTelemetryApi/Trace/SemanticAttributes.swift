/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// OpenTelemetry semantic attributes for HTTP and network instrumentation.
/// This is a minimal set containing only the attributes used by the Coralogix SDK.
public enum SemanticAttributes: String {
    // HTTP attributes
    case httpMethod = "http.method"
    case httpStatusCode = "http.status_code"
    case httpScheme = "http.scheme"
    case httpUrl = "http.url"
    case httpTarget = "http.target"
    case httpRequestContentLength = "http.request_content_length"
    case httpResponseContentLength = "http.response_content_length"
    case httpRequestBodySize = "http.request.body.size"
    case httpResponseBodySize = "http.response.body.size"
    
    // Network attributes  
    case netPeerName = "net.peer.name"
    case netPeerPort = "net.peer.port"
    case netSockPeerName = "net.sock.peer.name"
    case netSockPeerAddr = "net.sock.peer.addr"
    case netSockPeerPort = "net.sock.peer.port"
    case networkConnectionType = "network.connection.type"
    case networkConnectionSubtype = "network.connection.subtype"
}
