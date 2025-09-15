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
    /// Percentage of device RAM used (based on footprint).
    public let utilizationPercent: Double
}

final class MemoryDetector {
    private var timer: Timer?
    private var isRunning = false
    private let defaultInterval: TimeInterval = 0.1
    
    // MARK: - Stored samples (instantaneous per sample)
    private var footprintSamples: [Double] = []       // MB
    private var residentSamples: [Double] = []        // MB
    private var utilizationSamples: [Double] = []     // %

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
        t.tolerance = 1.0 // minute-level sampling can tolerate some slack
        RunLoop.main.add(t, forMode: .common)
        timer = t
        
        // Trigger an immediate first sample (optional; comment out if you want to wait a minute)
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

        let util = totalRAMMB > 0
            ? (footprintMB / totalRAMMB) * 100.0
            : 0.0

        return MemoryMeasurement(
            footprintMB: footprintMB,
            residentMB: residentMB,
            utilizationPercent: min(max(util, 0), 100)
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
                Keys.min.rawValue: minFootprintMB,
                Keys.max.rawValue: maxFootprintMB,
                Keys.avg.rawValue: avgFootprintMB,
                Keys.p95.rawValue: p95FootprintMB
            ],
            MobileVitalsType.residentMemory.stringValue: [
                Keys.mobileVitalsUnits.rawValue: MeasurementUnits.megaBytes.stringValue,
                Keys.min.rawValue: minResidentMB,
                Keys.max.rawValue: maxResidentMB,
                Keys.avg.rawValue: avgResidentMB,
                Keys.p95.rawValue: p95ResidentMB
            ],
            MobileVitalsType.memoryUtilization.stringValue: [
                Keys.mobileVitalsUnits.rawValue: MeasurementUnits.percentage.stringValue,
                Keys.min.rawValue: minUtilPercent,
                Keys.max.rawValue: maxUtilPercent,
                Keys.avg.rawValue: avgUtilPercent,
                Keys.p95.rawValue: p95UtilPercent
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
