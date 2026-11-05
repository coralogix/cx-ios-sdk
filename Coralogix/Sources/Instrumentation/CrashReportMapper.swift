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
    /// The signal code as PLCrashReporter names it (`SEGV_MAPERR`), or `#<n>` for a number it has
    /// no name for.
    var signalCode: String? { get }
    /// Set when the crash was an uncaught Objective-C exception (including a React Native fatal).
    var exceptionName: String? { get }
    var exceptionReason: String? { get }
    var processName: String? { get }
    var processID: UInt { get }
    var applicationIdentifier: String? { get }
    var threads: [CrashThread] { get }
    /// The main binary's load address and architecture, as the report's text gives them.
    var mainBinaryImage: (baseAddress: String, arch: String)? { get }
}

/// A crash report reduced to the values the crash span carries.
struct MappedCrash: Equatable {
    enum Kind: Equatable {
        case signal
        case objcException
        case rnFatal
    }

    let crashId: String
    let crashTime: Date?
    let kind: Kind
    /// Always the signal: PLCrashReporter records an uncaught exception as a SIGABRT report.
    let exceptionType: String
    /// Equal to `exceptionType`, as Android's native crash sets it.
    let errorType: String
    let errorMessage: String
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
    /// Android caps a crash message at 102 characters, counted in UTF-16 units as Kotlin counts them.
    static let maxMessageUTF16Units = 102
    /// Android's cap for each thread of a JVM crash; a native crash sends one thread uncapped.
    static let maxFramesPerThread = 200
    static let rnFatalPrefix = "RCTFatalException"

    static func map(_ report: CrashReportReading) -> MappedCrash {
        let crashKind = kind(of: report)
        let threads = orderedThreads(report.threads, kind: crashKind)
        let threadStrings = threads.map { thread in
            Helper.convertArrayToJsonString(array: thread.frames.map(frameDictionary))
        }
        return MappedCrash(crashId: crashId(for: report),
                           crashTime: report.timestamp,
                           kind: crashKind,
                           exceptionType: report.signalName,
                           errorType: report.signalName,
                           errorMessage: capped(message(for: report, kind: crashKind)),
                           processName: report.processName,
                           applicationIdentifier: report.applicationIdentifier,
                           pid: report.processID,
                           threadsJSON: Helper.convertArrayOfStringToJsonString(array: threadStrings),
                           triggeredByThread: threads.isEmpty ? nil : 0,
                           baseAddress: report.mainBinaryImage?.baseAddress,
                           arch: report.mainBinaryImage?.arch)
    }

    static func kind(of report: CrashReportReading) -> MappedCrash.Kind {
        guard let name = report.exceptionName, !name.isEmpty else { return .signal }
        return name.hasPrefix(rnFatalPrefix) ? .rnFatal : .objcException
    }

    static func message(for report: CrashReportReading, kind: MappedCrash.Kind) -> String {
        let reason = report.exceptionReason.flatMap { $0.isEmpty ? nil : $0 }
        switch kind {
        case .signal:
            return signalCode(report.signalName, report.signalCode).map { "\(report.signalName) (\($0))" }
                ?? report.signalName
        case .objcException:
            let name = report.exceptionName ?? report.signalName
            return reason.map { "\(name): \($0)" } ?? name
        case .rnFatal:
            // RN's exception name repeats the description the reason already carries.
            return reason.map { "\(rnFatalPrefix): \($0)" } ?? rnFatalPrefix
        }
    }

    /// The code's name when Android has the same one, so a crash reads the same on both
    /// platforms. PLCrashReporter already names codes by Darwin's numbering; what it cannot name
    /// it prints as `#<n>`, and a code with no name gives the bare signal.
    static func signalCode(_ signal: String, _ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        if code.hasPrefix("#") {
            return Int(code.dropFirst()).flatMap { darwinGenericCodeNames[$0] }
        }
        return androidCodeNames[signal]?.contains(code) == true ? code : nil
    }

    /// Cuts to `maxMessageUTF16Units`, never splitting a surrogate pair.
    static func capped(_ message: String) -> String {
        guard message.utf16.count > maxMessageUTF16Units else { return message }
        var scalars = String.UnicodeScalarView()
        var units = 0
        for scalar in message.unicodeScalars {
            units += UTF16.width(scalar)
            if units > maxMessageUTF16Units { break }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// A signal crash sends only the crashed thread, as Android's native crash does. An
    /// exception sends every thread, crashed first and capped, as Android's JVM crash does.
    private static func orderedThreads(_ threads: [CrashThread], kind: MappedCrash.Kind) -> [CrashThread] {
        guard let crashedIndex = threads.firstIndex(where: \.crashed) ?? threads.indices.first else {
            return []
        }
        let crashed = threads[crashedIndex]
        switch kind {
        case .signal:
            return [crashed]
        case .objcException, .rnFatal:
            var ordered = threads
            ordered.remove(at: crashedIndex)
            ordered.insert(crashed, at: 0)
            return ordered.map { thread in
                CrashThread(number: thread.number, crashed: thread.crashed,
                            frames: Array(thread.frames.prefix(maxFramesPerThread)))
            }
        }
    }

    // Android's si_code names for a fault, per signal. A name outside these is not sent.
    private static let androidCodeNames: [String: Set<String>] = [
        "SIGILL": ["ILL_ILLOPC", "ILL_ILLOPN", "ILL_ILLADR", "ILL_ILLTRP", "ILL_PRVOPC", "ILL_PRVREG", "ILL_COPROC", "ILL_BADSTK"],
        "SIGTRAP": ["TRAP_BRKPT", "TRAP_TRACE"],
        "SIGBUS": ["BUS_ADRALN", "BUS_ADRERR", "BUS_OBJERR"],
        "SIGFPE": ["FPE_INTDIV", "FPE_INTOVF", "FPE_FLTDIV", "FPE_FLTOVF", "FPE_FLTUND", "FPE_FLTRES", "FPE_FLTINV", "FPE_FLTSUB"],
        "SIGSEGV": ["SEGV_MAPERR", "SEGV_ACCERR"]
    ]

    // Darwin numbers the software-sent codes differently from Linux (SI_USER is 0x10001, not 0).
    private static let darwinGenericCodeNames: [Int: String] = [
        0x10001: "SI_USER",
        0x10002: "SI_QUEUE"
    ]

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
    var signalCode: String? { report.signalInfo.code }
    var exceptionName: String? { report.hasExceptionInfo ? report.exceptionInfo.exceptionName : nil }
    var exceptionReason: String? { report.hasExceptionInfo ? report.exceptionInfo.exceptionReason : nil }
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
