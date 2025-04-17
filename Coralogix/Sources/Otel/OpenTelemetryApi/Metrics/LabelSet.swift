/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// Normalized name value pairs of metric labels.
/// Phase 2
/// @available(*, deprecated, message: "LabelSet removed from Metric API in OTEP-90")
public class LabelSet: Hashable {
    /// Dictionary to store labels as key-value pairs.
    public private(set) var labels: [String: String] = [:]

    /// An empty `LabelSet` instance.
    public static var empty: LabelSet {
        return LabelSet(labels: [:])
    }
    
    /// Public initializer with provided labels.
    /// - Parameter labels: A dictionary of string key-value pairs.
    public init(labels: [String: String]) {
        self.labels = labels
    }
    
    public static func == (lhs: LabelSet, rhs: LabelSet) -> Bool {
        return lhs.labels == rhs.labels
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(labels)
    }
}
