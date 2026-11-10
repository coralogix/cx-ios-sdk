//
//  E2ECrashes.swift
//  CrashE2EApp
//
//  The crashes and hangs a scenario can ask for, by name.
//

import Foundation

enum E2ECrashes {
    static let longReason = "crash e2e: " + String(repeating: "a reason longer than the message cap ", count: 8)

    static func crash(_ kind: String) {
        switch kind {
        case "exception":
            NSException(name: .invalidArgumentException, reason: "crash e2e exception").raise()
        case "exceptionWithoutReason":
            NSException(name: .genericException, reason: nil).raise()
        case "longReason":
            NSException(name: .internalInconsistencyException, reason: longReason).raise()
        case "unrecognizedSelector":
            _ = NSNull().perform(Selector(("length")))
        case "rctFatal":
            let description = "Unhandled JS Exception: TypeError: crash e2e"
            NSException(name: NSExceptionName("RCTFatalException: \(description)"), reason: description).raise()
        case "backgroundException":
            let done = DispatchSemaphore(value: 0)
            Thread { NSException(name: .invalidArgumentException, reason: "crash e2e background").raise() }.start()
            _ = done.wait(timeout: .now() + 5)
        case "cxx": CrashLabNative.throwCppException()
        case "abort": abort()
        case "sigill": CrashLabNative.illegalInstruction()
        case "sigtrap": CrashLabNative.breakpoint()
        case "sigfpe": pthread_kill(pthread_self(), SIGFPE)
        case "sigbus": busError()
        case "pthread":
            var thread: pthread_t?
            pthread_create(&thread, nil, { _ in
                E2ECrashes.writeThroughNull()
                return nil
            }, nil)
            Thread.sleep(forTimeInterval: 5)
        case "survivableSignal":
            CrashLabNative.faultAndRecover()
        default:
            writeThroughNull()
        }
    }

    static func writeThroughNull() {
        UnsafeMutablePointer<Int>(bitPattern: 0x8)!.pointee = 1
    }

    private static func busError() {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("crash-e2e-sigbus")
        FileManager.default.createFile(atPath: path, contents: Data([1]))
        let fd = open(path, O_RDONLY)
        let page = Int(getpagesize())
        guard fd >= 0, let mapped = mmap(nil, page * 2, PROT_READ, MAP_PRIVATE, fd, 0), mapped != MAP_FAILED else { return }
        _ = mapped.load(fromByteOffset: page, as: UInt8.self)
    }
}
