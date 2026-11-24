//
//  HTTPEnums.swift
//
//
//  Created by Coralogix DEV TEAM on 18/05/2026.
//

import Foundation

/// Standard HTTP request methods. RawValue is uppercase to match what
/// `URLRequest.httpMethod` and the OTel `http.method` attribute convention
/// produce in practice; callers may construct via `HTTPMethod(rawValue:)`
/// from a normalized string.
public enum HTTPMethod: String, Codable {
    case get     = "GET"
    case post    = "POST"
    case put     = "PUT"
    case delete  = "DELETE"
    case patch   = "PATCH"
    case head    = "HEAD"
    case options = "OPTIONS"
    case connect = "CONNECT"
    case trace   = "TRACE"
}

/// URL scheme. Matches what `URL.scheme` returns (lowercase).
public enum URLScheme: String, Codable {
    case http
    case https
}
