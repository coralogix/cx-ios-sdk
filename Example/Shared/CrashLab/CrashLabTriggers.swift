//
//  CrashLabTriggers.swift
//  DemoApp
//
//  What each Crash Lab case does when tapped, or when the driver script launches the app with
//  `-crashLabCase <id>`, keyed by the case's id in `crash-lab/cases.json`. Shared by both demo
//  apps, so they behave identically. Cases a launch setting drives instead (crashes before init,
//  crash loops) have no entry here.
//

import Foundation
import Coralogix
import SessionReplay

enum CrashLabTriggers {
    /// Runs case `id`. Returns a line to show when the case does not end the process.
    @discardableResult
    static func run(_ id: String) -> String? {
        guard let trigger = triggers[id] else { return "No trigger for case \(id)" }
        return trigger()
    }

    static var ids: Set<String> { Set(triggers.keys) }

    /// A global span is ended once nothing holds it: the lab keeps the one it starts.
    private static var globalSpan: CoralogixGlobalSpan?
    static func keep(_ span: CoralogixGlobalSpan?) { globalSpan = span ?? globalSpan }

    /// The crash a launch setting asks for: an NSException, a signal or a C++ exception.
    static func crash(kind: String, message: String) {
        switch kind {
        case "exception": NSException(name: .internalInconsistencyException, reason: message).raise()
        case "cxx": CrashLabNative.throwCppException()
        default: writeThroughNull()
        }
    }

    private static let triggers: [String: () -> String?] = [
        "N1": { writeThroughNull(); return nil },
        "N2": { _ = recurse(0); return nil },
        "N3": { abort() },
        "N4": { CrashLabNative.throwCppException(); return nil },
        "N6": { busError(); return nil },
        "N7": { CrashLabNative.illegalInstruction(); return nil },
        "N8": { CrashLabNative.breakpoint(); return nil },
        // arm64 does not fault on integer division by zero: send the signal itself.
        "N9": { pthread_kill(pthread_self(), SIGFPE); return nil },
        "N10": { _ = strlen(UnsafePointer<CChar>(bitPattern: 0x10)!); return nil },
        "N11": { crashOnAThreadOfItsOwn(); return nil },
        "N12": { twoThreadsAtOnce(); return nil },
        "N13": {
            CrashLabNative.faultAndRecover()
            return "Faulted and recovered: the process lives on"
        },

        "J1": { raise("crash lab: main thread") },
        // Waited for, so the main thread is still in here when the crash reads the app's threads.
        "J2": {
            let crashed = DispatchSemaphore(value: 0)
            Thread { raise("crash lab: background thread") }.start()
            _ = crashed.wait(timeout: .now() + 5)
            return nil
        },
        "J3": {
            SessionReplay.shared?.startRecording()
            // Long enough for replay to be capturing when the crash comes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { raise("crash lab: crash while session replay records") }
            return "Recording; crashing in 3 s"
        },
        "J4": {
            SessionReplay.shared?.startRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                CoralogixRumManager.shared.sdk.createNewSession()
                raise("crash lab: crash during a session rotation")
            }
            return "Recording; rotating the session and crashing in 3 s"
        },
        "J11": {
            // 100 threads parked deep in their stacks, so the crash has a large set of threads to take.
            let parked = DispatchGroup()
            for _ in 0..<100 {
                parked.enter()
                Thread { parkDeep(120, parked: parked) }.start()
            }
            parked.wait()
            return raise("crash lab: crash with 100 deep threads")
        },
        "J13": {
            guard let span = CoralogixRumManager.shared.sdk.getCustomTracer()?.startGlobalSpan(name: "crash-lab-global-span") else {
                return "No global span: the tracer is unavailable or one is already active"
            }
            keep(span)
            return raise("crash lab: crash inside a global span")
        },

        "I1": { _ = NSNull().perform(Selector(("length"))); return nil },
        "I2": {
            let description = "Unhandled JS Exception: TypeError: crash lab is not a function"
            NSException(name: NSExceptionName("RCTFatalException: \(description)"), reason: description).raise()
            return nil
        },
        "I3": { NSException(name: .genericException, reason: nil).raise(); return nil },
        "I4": { raise("crash lab: " + String(repeating: "a reason longer than the message cap ", count: 8)) },
        "I5": {
            let missing: Int? = nil
            _ = missing!
            return nil
        },
        "I6": {
            CoralogixRumManager.shared.sdk.reportError(message: "crash lab: hybrid crash", stackTrace: [],
                                                       errorType: "Error", isCrash: true)
            return "Reported a hybrid crash: sent once, now"
        },

        // The driver terminates the app meanwhile, which stands in for the system's watchdog.
        "A1": { Thread.sleep(forTimeInterval: CrashLabSettings.hangSeconds); return nil },
        // Past the 5 s threshold, then the main thread answers again.
        "A3": { Thread.sleep(forTimeInterval: 8); return "Hung for 8 s and recovered" },

        // Two errors first, so the crash has a count of its own launch's to carry. This overload,
        // since `reportError(message:)` alone is sent as a log.
        "T3": {
            let sdk = CoralogixRumManager.shared.sdk
            for which in ["first", "second"] {
                sdk.reportError(message: "crash lab: \(which) error before the crash", stackTrace: [], errorType: "Error")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { writeThroughNull() }
            return "Reported two errors; crashing in 2 s"
        },

        "X2": { exit(0) },
    ]

    static func writeThroughNull() {
        UnsafeMutablePointer<Int>(bitPattern: 0x8)!.pointee = 1
    }

    private static func raise(_ reason: String) -> String? {
        NSException(name: .internalInconsistencyException, reason: reason).raise()
        return nil
    }

    private static func recurse(_ depth: Int) -> Int {
        depth < 0 ? 0 : recurse(depth + 1) + depth
    }

    /// Reads a page of a mapped file that lies past its end: a real SIGBUS.
    private static func busError() {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("crash-lab-sigbus")
        FileManager.default.createFile(atPath: path, contents: Data([1]))
        let fd = open(path, O_RDONLY)
        let page = Int(getpagesize())
        guard fd >= 0, let mapped = mmap(nil, page * 2, PROT_READ, MAP_PRIVATE, fd, 0), mapped != MAP_FAILED else { return }
        _ = mapped.load(fromByteOffset: page, as: UInt8.self)
    }

    private static func crashOnAThreadOfItsOwn() {
        var thread: pthread_t?
        pthread_create(&thread, nil, { _ in
            CrashLabTriggers.writeThroughNull()
            return nil
        }, nil)
        Thread.sleep(forTimeInterval: 2)
    }

    private static func twoThreadsAtOnce() {
        let go = DispatchSemaphore(value: 0)
        for _ in 0..<2 {
            Thread {
                go.wait()
                writeThroughNull()
            }.start()
        }
        go.signal()
        go.signal()
        Thread.sleep(forTimeInterval: 2)
    }

    private static func parkDeep(_ depth: Int, parked: DispatchGroup) {
        if depth > 0 { return parkDeep(depth - 1, parked: parked) }
        parked.leave()
        while true { Thread.sleep(forTimeInterval: 3600) }
    }
}
