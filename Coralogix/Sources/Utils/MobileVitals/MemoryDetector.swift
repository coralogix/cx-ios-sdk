//
//  MemoryDetector.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 13/08/2025.
//

import Foundation
import Darwin.Mach

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
    private let interval: TimeInterval
    private let minInterval: TimeInterval = 0.1
    var handleMemoryClosure: (() -> Void)?

    public init(interval: TimeInterval = 60.0) {
        self.interval = max(interval, minInterval)
    }

    public func startMonitoring() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkForMemory()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    deinit { stopMonitoring() }

    @objc private func checkForMemory() {
        guard let m = MemoryDetector.readMemoryMeasurement() else { return }
        self.handleMemoryClosure?()
        Log.d(String(
            format: "[Metric] Memory: %.1f MB | Utilization: %.2f%%",
            m.footprintMB,
            m.utilizationPercent
        ))

        reportMemory(m)
    }

    public static func readMemoryMeasurement() -> MemoryMeasurement? {
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

    private func reportMemory(_ m: MemoryMeasurement) {
        let uuid = UUID().uuidString.lowercased()

        let metrics: [(CXMobileVitalsType, Double)] = [
            (.residentMemoryMb, m.footprintMB),
            (.memoryUtilizationPercent, m.utilizationPercent)
        ]

        func format(_ v: Double, decimals: Int = 3) -> String {
            String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), v)
        }

        let post: (CXMobileVitalsType, Double) -> Void = { type, value in
            let payload = CXMobileVitals(type: type, value: format(value, decimals: type == .residentMemoryMb ? 1 : 2), uuid: uuid)
            if Thread.isMainThread {
                NotificationCenter.default.post(name: .cxRumNotificationMetrics, object: payload)
            } else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .cxRumNotificationMetrics, object: payload)
                }
            }
        }

        metrics.forEach { post($0.0, $0.1) }
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
