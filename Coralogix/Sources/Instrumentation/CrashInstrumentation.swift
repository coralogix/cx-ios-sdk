//
//  CrashInstumentation.swift
//
//
//  Created by Coralogix DEV TEAM on 08/04/2024.
//

import Foundation
import CrashReporter

extension CoralogixRum {
    public func initializeCrashInstumentation() {
        
        // It is strongly recommended that local symbolication only be enabled for non-release builds.
        // Use [] for release versions.
        let config = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: .all)
        guard let crashReporter = PLCrashReporter(configuration: config) else {
            Log.e("Could not create an instance of PLCrashReporter")
            return
        }
        
        crashReporter.enable()
        
        // Try loading the crash report.
        if crashReporter.hasPendingCrashReport() {
            do {
                let data = try crashReporter.loadPendingCrashReportDataAndReturnError()
                
                // Retrieving crash reporter data.
                let report = try PLCrashReport(data: data)
                var span = tracer().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
                span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.error.rawValue)
                span.setAttribute(key: Keys.source.rawValue, value: Keys.console.rawValue)
                span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.error.rawValue))
                
                // user_context
                self.addUserMetadata(to: &span)
                
                span.setAttribute(key: Keys.exceptionType.rawValue, value: report.signalInfo.name)
                if let crashTimestamp = report.systemInfo.timestamp {
                    span.setAttribute(key: Keys.crashTimestamp.rawValue, value: "\(crashTimestamp.timeIntervalSince1970.milliseconds)")
                }
                span.setAttribute(key: Keys.processName.rawValue, value: report.processInfo.processName)
                span.setAttribute(key: Keys.applicationIdentifier.rawValue, value: report.applicationInfo.applicationIdentifier)
                span.setAttribute(key: Keys.pid.rawValue, value: "\(report.processInfo.processID)")
                
                self.createStackTrace(report: report, span: span)
                
                if let text = PLCrashReportTextFormatter.stringValue(for: report, with: PLCrashReportTextFormatiOS) {
                    let substrings = text.components(separatedBy: "\n")
                    for value in substrings {
                        if let processName = report.processInfo.processName,
                           value.contains("+\(processName)") {
                            let details = extractMemoryAddressAndArchitecture(input: value)
                            if details.count == 7 {
                                let baseAddress = details[0]  // Extracting the base memory address
                                span.setAttribute(key: Keys.baseAddress.rawValue, value: "\(baseAddress)")
                                let arch = details[4]     // Extracting the architecture
                                span.setAttribute(key: Keys.arch.rawValue, value: "\(arch)")
                            }
                        }
                    }
                } else {
                    Log.e("CrashReporter: can't convert report to text")
                }
                span.end()
            } catch let error {
                Log.e("CrashReporter failed to load and parse with error: \(error)")
            }
        }
        
        // Purge the report.
        crashReporter.purgePendingCrashReport()
        
    }
    
    private func createStackTrace(report: PLCrashReport, span: Span) {
        var threads = [String]()
        for case let thread as PLCrashReportThreadInfo in report.threads {
            if thread.crashed {
                span.setAttribute(key: Keys.triggeredByThread.rawValue, value: thread.threadNumber)
            }
            
            let crashedThreadFrames = crashedThread(report: report, thread: thread)
            let data = self.parseFrameArray(crashedThreadFrameArray: crashedThreadFrames)
            threads.append(Helper.convertArrayToJsonString(array: data))
        }
        span.setAttribute(key: Keys.threads.rawValue, value: Helper.convertArrayOfStringToJsonString(array: threads))
    }
    
    func parseFrameArray(crashedThreadFrameArray: [StackFrame]) -> [[String: Any]] {
        var result = [[String: Any]]()
        for frame in crashedThreadFrameArray {
            var frameObj = [String: Any]()
            frameObj[Keys.frameNumber.rawValue] = frame.frameNumber
            frameObj[Keys.binary.rawValue] = frame.binary
            frameObj[Keys.functionAddressCalled.rawValue] = frame.functionAdresseCalled
            frameObj[Keys.base.rawValue] = frame.base
            frameObj[Keys.offset.rawValue] = frame.offset
            result.append(frameObj)
        }
        return result
    }
    
    func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        assert(junk == 0, "sysctl failed")
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
    
    struct StackFrame {
        let frameNumber: String
        let binary: String
        let functionAdresseCalled: String
        let base: String
        let offset: String
        let description: String
    }
    
    private func crashedThread(report: PLCrashReport, thread: PLCrashReportThreadInfo) -> [StackFrame] {
        var stackFrames = [StackFrame]()
        // stack.append("Thread \(thread.threadNumber) Crashed:")
        var frameNum = 0
        while frameNum < thread.stackFrames.count {
            if let frame = thread.stackFrames[frameNum] as? PLCrashReportStackFrameInfo {
                let stackFrame = formatStackFrame(frame: frame, frameNum: frameNum, report: report)
                stackFrames.append(stackFrame)
            }
            frameNum += 1
        }
        return stackFrames
    }
    
    private func formatStackFrame(frame: PLCrashReportStackFrameInfo, frameNum: Int, report: PLCrashReport) -> StackFrame {
        var baseAddress: UInt64 = 0
        var pcOffset: UInt64 = 0
        var imageName = "???"
        var symbolString = ""
        
        if let imageInfo = report.image(forAddress: frame.instructionPointer) {
            imageName = imageInfo.imageName
            imageName = URL(fileURLWithPath: imageName).lastPathComponent
            baseAddress = imageInfo.imageBaseAddress
            pcOffset = frame.instructionPointer - imageInfo.imageBaseAddress
        }
        
        var offset: String = ""
        var base: String = ""
        if let symbolInfo = frame.symbolInfo,
           let symbolName = symbolInfo.symbolName {
            let symOffset = frame.instructionPointer - frame.symbolInfo.startAddress
            offset = String(format: "%ld", symOffset)
            base = symbolName
            symbolString = String(format: "%@ + %ld", symbolName, symOffset)
        } else {
            offset = String(format: "%ld", pcOffset)
            base = String(format: "0x%lx", baseAddress)
            symbolString = String(format: "0x%lx + %ld", baseAddress, pcOffset)
        }
        let description = String(format: "%-4ld%-35@ 0x%016lx %@", frameNum, imageName, frame.instructionPointer, symbolString)
        let stackFrame = StackFrame(frameNumber: "\(frameNum)",
                                    binary: imageName,
                                    functionAdresseCalled: String(format: "0x%016lx", frame.instructionPointer),
                                    base: base,
                                    offset: offset,
                                    description: description)
        
        return stackFrame
    }
    
    private func extractMemoryAddressAndArchitecture(input: String) -> [String] {
        let pattern = #"[^\s]+"#
        let matches = input.matches(for: pattern)
        return matches
    }
}
