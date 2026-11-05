//
//  CrashReportMapper.swift
//  Coralogix
//

import Foundation
import CrashReporter
import CoralogixInternal

/// One frame of a crash report thread, already formatted the way the wire carries it.
struct CrashStackFrame: Equatable {
    let frameNumber: String
    let binary: String
    let functionAddressCalled: String
    let base: String
    let offset: String
}

struct CrashThread: Equatable {
    let number: Int
    let crashed: Bool
    let frames: [CrashStackFrame]
}

/// What the mapper needs from a crash report. A protocol so the mapping rules can be tested
/// with fakes; `PLCrashReportReader` reads a real PLCrashReporter report.
protocol CrashReportReading {
    /// The report's own UUID: the same on every launch that reads this report.
    var reportId: String? { get }
    var timestamp: Date? { get }
    var signalName: String { get }
    var processName: String? { get }
    var processID: UInt { get }
    var applicationIdentifier: String? { get }
    var threads: [CrashThread] { get }
    /// The main binary's load address and architecture, as the report's text gives them.
    var mainBinaryImage: (baseAddress: String, arch: String)? { get }
}

/// A crash report reduced to the values the crash span carries.
struct MappedCrash: Equatable {
    let crashId: String
    let crashTime: Date?
    let exceptionType: String
    let processName: String?
    let applicationIdentifier: String?
    let pid: UInt
    /// JSON array of threads, each a JSON array of frame objects.
    let threadsJSON: String
    let triggeredByThread: Int?
    let baseAddress: String?
    let arch: String?
}

enum CrashReportMapper {
    static func map(_ report: CrashReportReading) -> MappedCrash {
        let threads = report.threads.map { thread in
            Helper.convertArrayToJsonString(array: thread.frames.map(frameDictionary))
        }
        return MappedCrash(crashId: crashId(for: report),
                           crashTime: report.timestamp,
                           exceptionType: report.signalName,
                           processName: report.processName,
                           applicationIdentifier: report.applicationIdentifier,
                           pid: report.processID,
                           threadsJSON: Helper.convertArrayOfStringToJsonString(array: threads),
                           triggeredByThread: report.threads.first(where: \.crashed)?.number,
                           baseAddress: report.mainBinaryImage?.baseAddress,
                           arch: report.mainBinaryImage?.arch)
    }

    /// The report's UUID when it has one. Otherwise an id derived from what identifies this crash,
    /// so the same report still maps to the same id on every launch that reads it.
    static func crashId(for report: CrashReportReading) -> String {
        if let reportId = report.reportId, !reportId.isEmpty {
            return reportId
        }
        let millis = report.timestamp.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
        return "plcr-\(millis)-\(report.processID)-\(report.signalName)"
    }

    private static func frameDictionary(_ frame: CrashStackFrame) -> [String: Any] {
        [
            Keys.frameNumber.rawValue: frame.frameNumber,
            Keys.binary.rawValue: frame.binary,
            Keys.functionAddressCalled.rawValue: frame.functionAddressCalled,
            Keys.base.rawValue: frame.base,
            Keys.offset.rawValue: frame.offset
        ]
    }
}

/// Reads a PLCrashReporter report through `CrashReportReading`.
struct PLCrashReportReader: CrashReportReading {
    let report: PLCrashReport

    var reportId: String? {
        guard let uuid = report.uuidRef else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    var timestamp: Date? { report.systemInfo.timestamp }
    var signalName: String { report.signalInfo.name }
    var processName: String? { report.processInfo.processName }
    var processID: UInt { report.processInfo.processID }
    var applicationIdentifier: String? { report.applicationInfo.applicationIdentifier }

    var threads: [CrashThread] {
        report.threads.compactMap { $0 as? PLCrashReportThreadInfo }.map { thread in
            let frames = thread.stackFrames.enumerated().compactMap { index, frame in
                (frame as? PLCrashReportStackFrameInfo).map { formatStackFrame($0, frameNum: index) }
            }
            return CrashThread(number: thread.threadNumber, crashed: thread.crashed, frames: frames)
        }
    }

    var mainBinaryImage: (baseAddress: String, arch: String)? {
        guard let processName = report.processInfo.processName,
              let text = PLCrashReportTextFormatter.stringValue(for: report, with: PLCrashReportTextFormatiOS) else {
            Log.e("CrashReporter: can't convert report to text")
            return nil
        }
        // A binary-image line: "<base> - <end> +<name> <arch> <uuid> <path>".
        var image: (baseAddress: String, arch: String)?
        for line in text.components(separatedBy: "\n") where line.contains("+\(processName)") {
            let fields = line.matches(for: #"[^\s]+"#)
            if fields.count == 7 {
                image = (fields[0], fields[4])
            }
        }
        return image
    }

    private func formatStackFrame(_ frame: PLCrashReportStackFrameInfo, frameNum: Int) -> CrashStackFrame {
        var baseAddress: UInt64 = 0
        var pcOffset: UInt64 = 0
        var imageName = "???"

        if let imageInfo = report.image(forAddress: frame.instructionPointer) {
            imageName = URL(fileURLWithPath: imageInfo.imageName).lastPathComponent
            baseAddress = imageInfo.imageBaseAddress
            pcOffset = frame.instructionPointer - imageInfo.imageBaseAddress
        }

        let offset: String
        let base: String
        if let symbolInfo = frame.symbolInfo, let symbolName = symbolInfo.symbolName {
            offset = String(format: "%ld", frame.instructionPointer - symbolInfo.startAddress)
            base = symbolName
        } else {
            offset = String(format: "%ld", pcOffset)
            base = String(format: "0x%lx", baseAddress)
        }
        return CrashStackFrame(frameNumber: "\(frameNum)",
                               binary: imageName,
                               functionAddressCalled: String(format: "0x%016lx", frame.instructionPointer),
                               base: base,
                               offset: offset)
    }
}
