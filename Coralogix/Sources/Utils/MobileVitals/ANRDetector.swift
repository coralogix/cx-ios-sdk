//
//  ANRDetector.swift
//
//
//  Created by Coralogix DEV TEAM on 27/08/2024.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import CrashReporter
import CoralogixInternal

/// Reports the main thread blocked for `threshold`, once per hang, the way the Android SDK's
/// watchdog does.
///
/// Its own queue asks the main queue to answer every `pollInterval`; a main queue that has not
/// answered for `threshold` is hung. The ANR is reported as it is detected, with every thread as
/// they are at that moment, main first, so it leaves even when the app never recovers. A hang
/// seen while a debugger is attached is not reported, nor is the rest of it after the debugger
/// leaves. Monitoring pauses only while the app is in the background: a hang under a system
/// alert or Control Center still counts.
final class ANRDetector {
    static let defaultThreshold: TimeInterval = 5
    static let defaultPollInterval: TimeInterval = 0.5

    let threshold: TimeInterval
    let pollInterval: TimeInterval

    private let uptime: () -> TimeInterval
    private let mainQueue: DispatchQueue
    private let isDebuggerAttached: () -> Bool
    private let captureThreads: () -> String?
    private let notificationCenter: NotificationCenter
    let eventReporter: EventReporter?

    private let queue = DispatchQueue(label: Keys.queueANRDetectorQueue.rawValue)

    /// The one watchdog running in the process. A hang is the process's, so a second watchdog — an
    /// SDK initialized again without `shutdown` — would only report it twice.
    private static let runningLock = NSLock()
    private static weak var running: ANRDetector?

    private let lock = NSLock()
    // Guarded by `lock`.
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    private var isPaused = false

    // Confined to `queue`.
    private var lastAnswer: TimeInterval = 0
    private var lastTick: TimeInterval = 0
    private var awaitingAnswer = false
    /// The hang under way has been reported, or seen under a debugger.
    private var hangHandled = false

    init(threshold: TimeInterval = ANRDetector.defaultThreshold,
         pollInterval: TimeInterval = ANRDetector.defaultPollInterval,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         mainQueue: DispatchQueue = .main,
         isDebuggerAttached: @escaping () -> Bool = ANRDetector.isDebuggerAttached,
         captureThreads: @escaping () -> String? = ANRThreads.capture,
         notificationCenter: NotificationCenter = .default,
         eventReporter: EventReporter? = nil) {
        let poll = max(pollInterval, 0.01)
        if threshold < 2 * poll {
            Log.w("[ANR] threshold \(threshold) s is below twice the \(poll) s poll; using \(2 * poll) s")
        }
        self.threshold = max(threshold, 2 * poll)
        self.pollInterval = poll
        self.uptime = uptime
        self.mainQueue = mainQueue
        self.isDebuggerAttached = isDebuggerAttached
        self.captureThreads = captureThreads
        self.notificationCenter = notificationCenter
        self.eventReporter = eventReporter
    }

    deinit {
        stopMonitoring()
    }

    var isMonitoring: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timer != nil
    }

    /// Starts watching, and stops any other watchdog in the process. Works from any thread; a
    /// second call does nothing.
    func startMonitoring() {
        Self.runningLock.lock()
        let previous = Self.running
        Self.running = self
        Self.runningLock.unlock()
        if let previous, previous !== self {
            previous.stopMonitoring()
        }

        lock.lock()
        defer { lock.unlock() }
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval, leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        observers = observeBackground()
        isPaused = false
        queue.async { [weak self] in self?.restart() }
        // Never suspended: cancelling a suspended source traps.
        timer.resume()
    }

    /// Stops watching. Works from any thread, paused or not.
    func stopMonitoring() {
        lock.lock()
        let timer = self.timer
        let observers = self.observers
        self.timer = nil
        self.observers = []
        isPaused = false
        lock.unlock()

        observers.forEach(notificationCenter.removeObserver)
        timer?.cancel()
    }

    /// Reports the hang detected at `detectedAt`, with the threads as they are now.
    func handleANR(detectedAt: Date = Date()) {
        Log.d("[ANR] main thread unresponsive for at least \(threshold) s")
        guard let eventReporter = eventReporter else {
            Log.d("[ANR] no event reporter; ANR not reported")
            return
        }
        eventReporter.report(ANRErrorEvent(timestamp: detectedAt, threads: captureThreads()))
    }

    // MARK: - Watching

    private func tick() {
        guard !paused else { return }
        let now = uptime()
        // A gap this long means the process was not running (suspended): no hang to measure.
        if now - lastTick > 2 * pollInterval {
            restart(at: now)
        }
        lastTick = now

        if !awaitingAnswer {
            awaitingAnswer = true
            mainQueue.async { [weak self] in self?.answered() }
        }

        guard now - lastAnswer > threshold, !hangHandled else { return }
        hangHandled = true
        guard !isDebuggerAttached() else {
            Log.d("[ANR] main thread hung while a debugger is attached; not reported")
            return
        }
        handleANR()
    }

    /// Runs on the main queue.
    private func answered() {
        let at = uptime()
        queue.async { [weak self] in
            guard let self = self else { return }
            self.lastAnswer = at
            self.awaitingAnswer = false
            self.hangHandled = false
        }
    }

    private func restart(at now: TimeInterval? = nil) {
        let now = now ?? uptime()
        lastAnswer = now
        lastTick = now
        hangHandled = false
    }

    private var paused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isPaused
    }

    private func observeBackground() -> [NSObjectProtocol] {
        #if canImport(UIKit)
        let background = notificationCenter.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                        object: nil, queue: nil) { [weak self] _ in
            self?.setPaused(true)
        }
        let foreground = notificationCenter.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                                        object: nil, queue: nil) { [weak self] _ in
            self?.setPaused(false)
        }
        return [background, foreground]
        #else
        return []
        #endif
    }

    private func setPaused(_ paused: Bool) {
        lock.lock()
        isPaused = paused
        lock.unlock()
        if !paused {
            queue.async { [weak self] in self?.restart() }
        }
    }

    // MARK: - Debugger

    /// Whether a debugger is tracing this process, as Android's `reportInDebug = false` checks.
    static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}

/// Every thread of the process as an ANR carries them.
enum ANRThreads {
    /// A live report suspends every other thread while it reads them. Two at once suspend each
    /// other and neither resumes, hanging the app, so this process makes one at a time.
    private static let liveReportLock = NSLock()

    /// Runs `body`, which makes a live report, while no other live report of ours is being made.
    static func withLiveReportLock<T>(_ body: () throws -> T) rethrows -> T {
        liveReportLock.lock()
        defer { liveReportLock.unlock() }
        return try body()
    }

    /// Reads every thread from a live report, while the main thread is still blocked. The
    /// reporter is never enabled and does not symbolicate, so this takes milliseconds.
    static func capture() -> String? {
        guard let reporter = PLCrashReporter(configuration: PLCrashReporterConfig(signalHandlerType: .BSD,
                                                                                  symbolicationStrategy: [])),
              let data = withLiveReportLock({ try? reporter.generateLiveReportAndReturnError() }),
              let report = try? PLCrashReport(data: data) else {
            Log.w("[ANR] could not read the threads")
            return nil
        }
        return CrashReportMapper.watchdogThreadsJSON(PLCrashReportReader(report: report).threads)
    }
}
