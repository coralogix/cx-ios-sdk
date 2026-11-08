//
//  CrashDeliveryScheduler.swift
//  Coralogix
//

import Foundation
import CoralogixInternal

/// The time the scheduler reads and waits on. Injected so tests can step through the retry slots.
protocol DeliveryClock: AnyObject {
    func now() -> Date
    /// Runs `work` once `date` is reached, unless the returned timer is cancelled first.
    func schedule(at date: Date, _ work: @escaping () -> Void) -> DeliveryTimer
}

final class DeliveryTimer {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }
}

final class SystemDeliveryClock: DeliveryClock {
    func now() -> Date { Date() }

    func schedule(at date: Date, _ work: @escaping () -> Void) -> DeliveryTimer {
        let timer = DeliveryTimer()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, date.timeIntervalSinceNow)) {
            guard !timer.isCancelled else { return }
            work()
        }
        return timer
    }
}

/// Sends one stored crash, rebuilt from its record, and answers once.
protocol StoredCrashSending: AnyObject {
    func sendStoredCrash(_ item: CrashDeliveryScheduler.Item,
                         as record: StoredCrashRecord,
                         completion: @escaping (CrashUploadAnswer) -> Void)
    /// Cancels the send in flight; it answers `notAttempted`.
    func cancelStoredCrashSend()
}

/// Sends the stored crashes of earlier launches, one at a time, the way the Android SDK does.
///
/// Crashes go back to back until one fails. The pass then waits for the next retry slot, +30 s
/// or +2 min from the first send of the first crash that failed, shared by the whole queue, and
/// goes on from that crash. After the last slot, what is left waits for the next launch.
/// `Retry-After` holds back every later send. Each send rebuilds the crash from the store, so
/// sampling, `ignoreErrors` and `beforeSend` apply again every time.
///
/// The pass runs under a background task, so moving to the background does not stop it. When the
/// system takes that time back, the send in flight is cancelled without counting a failure.
final class CrashDeliveryScheduler {
    struct Item: Equatable {
        let crashId: String
        let copy: URL
    }

    static let retrySlots: [TimeInterval] = [30, 120]
    static var lastSlot: TimeInterval { retrySlots.last ?? 0 }
    /// The stored-crash request's 120 s bound, plus 10 s.
    static let answerTimeout: TimeInterval = 130
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    static let maxFailedUploads = 16

    private final class Pass {
        let items: [Item]
        let onEnd: (() -> Void)?
        var index = 0
        var firstSend: Date?
        /// When the first crash that failed was first sent; the retry slots count from here.
        var anchor: Date?
        var attempt = 0
        var awaitingAnswer = false
        var task: BackgroundTask?
        var timers: [DeliveryTimer] = []

        init(items: [Item], onEnd: (() -> Void)?) {
            self.items = items
            self.onEnd = onEnd
        }
    }

    private let store: CrashDeliveryStore
    private let clock: DeliveryClock
    private let backgroundTasks: BackgroundTaskRunning
    private let isOnline: () -> Bool
    private weak var sender: StoredCrashSending?

    private let queue = DispatchQueue(label: Keys.queueCrashDeliveryQueue.rawValue)
    /// Entered for each block put on `queue`, and for each send awaiting its answer: test hooks
    /// wait on them.
    private let queuedWork = DispatchGroup()
    private let inFlight = DispatchGroup()
    // Confined to `queue`.
    private var pass: Pass?
    private var holdUntil: Date?

    init(store: CrashDeliveryStore,
         sender: StoredCrashSending,
         clock: DeliveryClock = SystemDeliveryClock(),
         backgroundTasks: BackgroundTaskRunning = ApplicationBackgroundTaskRunner(),
         isOnline: @escaping () -> Bool) {
        self.store = store
        self.sender = sender
        self.clock = clock
        self.backgroundTasks = backgroundTasks
        self.isOnline = isOnline
    }

    /// Starts sending `items`, in the order given. `onEnd` runs once the pass is over: everything
    /// sent, or the rest left for the next launch. Does not block.
    func start(_ items: [Item], onEnd: (() -> Void)? = nil) {
        enqueue {
            guard self.pass == nil, !items.isEmpty else {
                onEnd?()
                return
            }
            let pass = Pass(items: items, onEnd: onEnd)
            self.pass = pass
            pass.task = self.backgroundTasks.begin(name: "CoralogixCrashDelivery") { [weak self] in
                self?.stop()
            }
            self.run(pass)
        }
    }

    /// Ends the pass, cancelling the send in flight. Nothing is counted; the rest is sent on a
    /// later launch.
    func stop() {
        enqueue {
            guard let pass = self.pass else { return }
            if pass.awaitingAnswer {
                self.sender?.cancelStoredCrashSend()
            }
            self.end(pass)
        }
    }

    /// Test hook: returns once nothing is left on the scheduler's queue. A send waiting on an
    /// answer the test itself will give does not hold it up.
    func waitUntilSettled() {
        queuedWork.wait()
    }

    /// Test hook: also waits for the answer to the send in flight.
    func waitUntilAnswered() {
        repeat {
            queuedWork.wait()
            inFlight.wait()
        } while queuedWork.wait(timeout: .now()) == .timedOut || inFlight.wait(timeout: .now()) == .timedOut
    }

    private func enqueue(_ block: @escaping () -> Void) {
        queuedWork.enter()
        queue.async {
            block()
            self.queuedWork.leave()
        }
    }

    // MARK: - The pass

    private func run(_ pass: Pass) {
        while pass.index < pass.items.count {
            let item = pass.items[pass.index]
            // A records file that cannot be read yet: leave this crash for a later launch.
            guard let record = store.record(for: item.crashId) else {
                pass.index += 1
                continue
            }
            if isExpired(record) {
                purge(item)
                pass.index += 1
                continue
            }
            guard isOnline() else {
                end(pass)
                return
            }
            let now = clock.now()
            if let hold = holdUntil, hold > now {
                wait(pass, until: hold)
                return
            }
            send(item, as: record, in: pass, at: now)
            return
        }
        end(pass)
    }

    private func send(_ item: Item, as record: StoredCrashRecord, in pass: Pass, at sendTime: Date) {
        guard let sender = sender else {
            end(pass)
            return
        }
        pass.attempt += 1
        pass.awaitingAnswer = true
        pass.firstSend = pass.firstSend ?? sendTime
        let attempt = pass.attempt
        inFlight.enter()

        let timeout = clock.schedule(at: sendTime.addingTimeInterval(Self.answerTimeout)) { [weak self] in
            self?.enqueue {
                self?.answered(nil, to: item, sentAt: sendTime, attempt: attempt, in: pass)
            }
        }
        pass.timers.append(timeout)
        sender.sendStoredCrash(item, as: record) { [weak self] answer in
            self?.enqueue {
                self?.answered(answer, to: item, sentAt: sendTime, attempt: attempt, in: pass)
            }
        }
    }

    private func answered(_ answer: CrashUploadAnswer?, to item: Item, sentAt: Date, attempt: Int, in pass: Pass) {
        guard self.pass === pass, pass.attempt == attempt, pass.awaitingAnswer else {
            // An answer that came after the pass gave up on it still counts if it is final.
            if let answer, answer.outcome.isFinished {
                purge(item)
            }
            return
        }
        pass.awaitingAnswer = false
        pass.timers.forEach { $0.cancel() }
        pass.timers = []
        defer { inFlight.leave() }

        guard let answer = answer else {
            Log.w("[CrashDelivery] no answer for crash \(item.crashId) within \(Int(Self.answerTimeout)) s — kept for a later launch")
            end(pass)
            return
        }
        let answeredAt = clock.now()
        if let retryAfter = answer.retryAfter {
            holdUntil = max(holdUntil ?? .distantPast, answeredAt.addingTimeInterval(retryAfter))
        }

        switch answer.outcome {
        case .delivered, .rejected, .policyDropped:
            purge(item)
            pass.index += 1
            run(pass)
        case .notAttempted:
            guard isOnline() else {
                end(pass)
                return
            }
            // Not retried this launch; the next crash goes now.
            pass.index += 1
            run(pass)
        case .failed(let counted):
            if counted {
                store.countFailedUpload(of: item.crashId)
            }
            pass.anchor = pass.anchor ?? sentAt
            retry(pass, after: answeredAt)
        }
    }

    /// Waits for the first slot still ahead of `answeredAt`, or for `Retry-After` if later.
    private func retry(_ pass: Pass, after answeredAt: Date) {
        guard let anchor = pass.anchor,
              let slot = Self.retrySlots.map({ anchor.addingTimeInterval($0) }).first(where: { $0 > answeredAt }) else {
            end(pass)
            return
        }
        wait(pass, until: max(slot, holdUntil ?? slot))
    }

    /// Resumes the pass at `date`, unless that is past the last slot.
    private func wait(_ pass: Pass, until date: Date) {
        let start = pass.anchor ?? pass.firstSend ?? clock.now()
        guard date <= start.addingTimeInterval(Self.lastSlot) else {
            end(pass)
            return
        }
        let timer = clock.schedule(at: date) { [weak self] in
            self?.enqueue {
                guard let self = self, self.pass === pass else { return }
                self.run(pass)
            }
        }
        pass.timers.append(timer)
    }

    private func end(_ pass: Pass) {
        guard self.pass === pass else { return }
        self.pass = nil
        pass.timers.forEach { $0.cancel() }
        pass.timers = []
        if pass.awaitingAnswer {
            pass.awaitingAnswer = false
            inFlight.leave()
        }
        pass.task?.end()
        pass.onEnd?()
    }

    // MARK: - Records

    private func isExpired(_ record: StoredCrashRecord) -> Bool {
        record.failedUploads >= Self.maxFailedUploads
            || clock.now().timeIntervalSince(record.crashTime) > Self.maxAge
    }

    private func purge(_ item: Item) {
        store.removeCopy(item.copy)
        store.removeRecord(for: item.crashId)
    }
}
