//
//  MemoryDetector.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 13/08/2025.
//

import Foundation
import Darwin.Mach
import UIKit

public struct MemoryMeasurement {
    /// iOS working set (in MB). Use this as “Resident Memory”.
    public let footprintMB: Double
    /// Traditional RSS (in MB), optional/for reference.
    public let residentMB: Double
    /// App memory footprint as % of total device physical RAM.
    /// Note: iOS reserves 1-2GB for system, so practical app maximum is ~70-80%.
    /// Values >100% should not occur but cap removed to avoid hiding measurement errors.
    public let utilizationPercent: Double
}

final class MemoryDetector {
    private var timer: Timer?
    private var isRunning = false
    // Battery-optimized: 1s interval captures all memory trends while reducing sampling by 10×
    // Memory changes slowly (seconds), so 1s provides accurate min/max/avg/p95 statistics
    // See CX-31659 for analysis and rationale
    private let defaultInterval: TimeInterval = 1.0
    
    // MARK: - Stored samples (instantaneous per sample)
    internal var footprintSamples: [Double] = []       // MB
    internal var residentSamples: [Double] = []        // MB
    internal var utilizationSamples: [Double] = []     // % of total device RAM

    // MARK: - Public stats
    // Footprint (MB)
    var minFootprintMB: Double { footprintSamples.min() ?? 0 }
    var maxFootprintMB: Double { footprintSamples.max() ?? 0 }
    var avgFootprintMB: Double { footprintSamples.isEmpty ? 0 : footprintSamples.reduce(0, +) / Double(footprintSamples.count) }
    var p95FootprintMB: Double { percentile95(of: footprintSamples) }
    
    // Resident (MB)
    var minResidentMB: Double { residentSamples.min() ?? 0 }
    var maxResidentMB: Double { residentSamples.max() ?? 0 }
    var avgResidentMB: Double { residentSamples.isEmpty ? 0 : residentSamples.reduce(0, +) / Double(residentSamples.count) }
    var p95ResidentMB: Double { percentile95(of: residentSamples) }
    
    // Utilization (%)
    var minUtilPercent: Double { utilizationSamples.min() ?? 0 }
    var maxUtilPercent: Double { utilizationSamples.max() ?? 0 }
    var avgUtilPercent: Double { utilizationSamples.isEmpty ? 0 : utilizationSamples.reduce(0, +) / Double(utilizationSamples.count) }
    var p95UtilPercent: Double { percentile95(of: utilizationSamples) }

    var handleMemoryClosure: (() -> Void)?

    public func startMonitoring() {
        DispatchQueue.main.async {
            guard !self.isRunning else { return }
            self.isRunning = true
            
            self.startTimer()
            
            // Pause/resume like your other detectors
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(self.appWillResignActive),
                                                   name: UIApplication.willResignActiveNotification,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(self.appDidBecomeActive),
                                                   name: UIApplication.didBecomeActiveNotification,
                                                   object: nil)
        }
    }

    public func stopMonitoring() {
        NotificationCenter.default.removeObserver(self)
        stopTimer()
        isRunning = false
        reset()
    }
    
    public func reset() {
        footprintSamples.removeAll()
        residentSamples.removeAll()
        utilizationSamples.removeAll()
    }

    deinit { stopMonitoring() }
    
    // MARK: - Timer helpers
    private func startTimer() {
        stopTimer()
        let t = Timer.scheduledTimer(withTimeInterval: defaultInterval, repeats: true) { [weak self] _ in
            self?.sampleOnce()
        }
        // Allow 1s tolerance for timer firing - battery-friendly for 1-second sampling
        t.tolerance = 1.0
        RunLoop.main.add(t, forMode: .common)
        timer = t
        
        // Trigger an immediate first sample to avoid waiting for the first 1-second interval
        sampleOnce()
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - App lifecycle
    @objc private func appWillResignActive() {
        stopTimer()
    }
    
    @objc private func appDidBecomeActive() {
        guard isRunning else { return }
        startTimer()
    }

    @objc private func sampleOnce() {
        guard let m = MemoryDetector.readMemoryMeasurement() else { return }
        self.handleMemoryClosure?()
        footprintSamples.append(m.footprintMB)
        residentSamples.append(m.residentMB)
        utilizationSamples.append(m.utilizationPercent)

//        Log.d(String(
//            format: "[MEM DEBUG] footprint=%.1fMB (min=%.1f max=%.1f avg=%.1f p95=%.1f) | resident=%.1fMB (min=%.1f max=%.1f avg=%.1f p95=%.1f) | util=%.2f%% (min=%.2f max=%.2f avg=%.2f p95=%.2f)",
//            m.footprintMB, minFootprintMB, maxFootprintMB, avgFootprintMB, p95FootprintMB,
//            m.residentMB,   minResidentMB,  maxResidentMB,  avgResidentMB,  p95ResidentMB,
//            m.utilizationPercent, minUtilPercent, maxUtilPercent, avgUtilPercent, p95UtilPercent
//        ))
    }

    static func readMemoryMeasurement() -> MemoryMeasurement? {
        guard let vm = taskVMInfo() else { return nil }

        let bytesPerMB = 1024.0 * 1024.0
        let footprintMB = Double(vm.phys_footprint) / bytesPerMB
        let residentMB  = Double(vm.resident_size) / bytesPerMB
        let totalRAMMB  = Double(ProcessInfo.processInfo.physicalMemory) / bytesPerMB

        // Memory utilization as % of total device physical RAM
        // Note: iOS reserves ~1-2GB for system, so app footprint relative to total device capacity
        // Cap removed to avoid hiding measurement errors (values >100% theoretically impossible)
        // See CX-31664 for analysis and rationale
        let util = totalRAMMB > 0
            ? (footprintMB / totalRAMMB) * 100.0
            : 0.0

        return MemoryMeasurement(
            footprintMB: footprintMB,
            residentMB: residentMB,
            utilizationPercent: max(util, 0)
        )
    }
    
    private func percentile95(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int(ceil(0.95 * Double(sorted.count)))
        return sorted[max(0, min(sorted.count - 1, rank - 1))]
    }

    func statsDictionary() -> [String: Any] {
        return [
            MobileVitalsType.footprintMemory.stringValue: [
                Keys.mobileVitalsUnits.rawValue: MeasurementUnits.megaBytes.stringValue,
                Keys.min.rawValue: minFootprintMB.roundedTo(),
                Keys.max.rawValue: maxFootprintMB.roundedTo(),
                Keys.avg.rawValue: avgFootprintMB.roundedTo(),
                Keys.p95.rawValue: p95FootprintMB.roundedTo()
            ],
            MobileVitalsType.residentMemory.stringValue: [
                Keys.mobileVitalsUnits.rawValue: MeasurementUnits.megaBytes.stringValue,
                Keys.min.rawValue: minResidentMB.roundedTo(),
                Keys.max.rawValue: maxResidentMB.roundedTo(),
                Keys.avg.rawValue: avgResidentMB.roundedTo(),
                Keys.p95.rawValue: p95ResidentMB.roundedTo()
            ],
            MobileVitalsType.memoryUtilization.stringValue: [
                Keys.mobileVitalsUnits.rawValue: MeasurementUnits.percentage.stringValue,
                Keys.min.rawValue: minUtilPercent.roundedTo(),
                Keys.max.rawValue: maxUtilPercent.roundedTo(),
                Keys.avg.rawValue: avgUtilPercent.roundedTo(),
                Keys.p95.rawValue: p95UtilPercent.roundedTo()
            ]
        ]
    }
}

@inline(__always)
private func taskVMInfo() -> task_vm_info_data_t? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? info : nil
}
