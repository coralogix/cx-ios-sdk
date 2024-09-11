//
//  CXSampler.swift
//
//
//  Created by Coralogix Dev Team on 14/08/2024.
//

import Foundation

protocol CXSamplerProtocol {
    func shouldInitialized() -> Bool
}

public struct CXSampler: CXSamplerProtocol {
    /// Value between `0.0` and `100.0`,
    ///  where `0.0` means SDK will not initialized and `100.0` means ALL events will be sent.
    public let sampleRate: Int

    public init(sampleRate: Int) {
        self.sampleRate = max(0, min(100, sampleRate))
    }

    /// Based on the sampling rate,
    /// it returns random value deciding if the SDK should be "initialized" or not.
    /// - Returns: `true` if SDK should be initialized and `false` if it should be dropped.
    public func shouldInitialized() -> Bool {
        return Int.random(in: 0..<100) < sampleRate
    }
}
