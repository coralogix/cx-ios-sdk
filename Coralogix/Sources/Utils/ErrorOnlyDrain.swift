//
//  ErrorOnlyDrain.swift
//  Coralogix
//

import Foundation
import CoralogixInternal

/// Sends what a session held until its error (`ErrorOnlyBuffer`), in paced requests on a queue of
/// its own, so live events are never held up behind it.
///
/// One request at a time, oldest events first, each closed at 500 events or 1.5 MB; the next goes
/// a second after the previous one is answered. A request is removed from the buffer only once it
/// is delivered or refused for good, so a drain cut short — background, kill, crash — resumes
/// where it stopped on a later foreground or launch, without sending anything twice.
///
/// Failures follow the stored-crash rules (`CrashDeliveryScheduler`): 408, 429, 5xx and transport
/// errors are retried at +30 s and +2 min from the first failure, honouring `Retry-After`; after
/// that the rest waits for a later launch. A session's buffer is given up after 16 counted failures
/// or 7 days. Offline, cancelled and unanswered attempts are not counted.
final class ErrorOnlyDrain {
    static let maxEventsPerRequest = 500
    static let maxBytesPerRequest = 1_536 * 1_024
    static let gapBetweenRequests: TimeInterval = 1

    private final class Pass {
        let sessionId: String
        /// When the first request that failed was sent; the retry slots count from here.
        var anchor: Date?
        var task: BackgroundTask?
        var timer: DeliveryTimer?

        init(sessionId: String) {
            self.sessionId = sessionId
        }
    }

    private let buffer: ErrorOnlyBuffer
    private let clock: DeliveryClock
    private let backgroundTasks: BackgroundTaskRunning
    private let isOnline: () -> Bool
    private let upload: ([[String: Any]]) -> SpanUploadResult
    private let cancelUpload: () -> Void

    private let queue = DispatchQueue(label: Keys.queueErrorOnlyDrainQueue.rawValue)
    private let queuedWork = DispatchGroup()
    // Confined to `queue`.
    private var waiting: [String] = []
    private var pass: Pass?
    private var holdUntil: Date?
    private var stopped = false

    init(buffer: ErrorOnlyBuffer,
         clock: DeliveryClock = SystemDeliveryClock(),
         backgroundTasks: BackgroundTaskRunning = ApplicationBackgroundTaskRunner(),
         isOnline: @escaping () -> Bool,
         upload: @escaping ([[String: Any]]) -> SpanUploadResult,
         cancelUpload: @escaping () -> Void = {}) {
        self.buffer = buffer
        self.clock = clock
        self.backgroundTasks = backgroundTasks
        self.isOnline = isOnline
        self.upload = upload
        self.cancelUpload = cancelUpload
    }

    /// Queues `sessionIds` for draining, after any already queued. Does not block.
    func start(_ sessionIds: [String]) {
        guard !sessionIds.isEmpty else { return }
        enqueue {
            guard !self.stopped else { return }
            for id in sessionIds where self.pass?.sessionId != id && !self.waiting.contains(id) {
                self.waiting.append(id)
            }
            self.runNext()
        }
    }

    /// Ends the drain for this SDK instance, cancelling the request in flight. What is left stays
    /// on disk for a later launch.
    func stop() {
        cancelUpload()
        enqueue {
            self.stopped = true
            self.waiting = []
            if let pass = self.pass { self.end(pass) }
        }
    }

    /// The system took the background time back: the request in flight is cancelled without
    /// counting, and the session goes back to the front of the queue for the next `start`.
    private func suspend(_ pass: Pass) {
        cancelUpload()
        enqueue {
            guard self.pass === pass else { return }
            self.waiting.insert(pass.sessionId, at: 0)
            self.end(pass)
        }
    }

    /// Test hook: returns once nothing is left on the drain's queue. A request scheduled for later
    /// on the clock does not hold it up.
    func waitUntilSettled() {
        queuedWork.wait()
    }

    private func enqueue(_ block: @escaping () -> Void) {
        queuedWork.enter()
        queue.async {
            block()
            self.queuedWork.leave()
        }
    }

    // MARK: - The pass

    private func runNext() {
        guard pass == nil, !stopped, !waiting.isEmpty else { return }
        let pass = Pass(sessionId: waiting.removeFirst())
        self.pass = pass
        pass.task = backgroundTasks.begin(name: "CoralogixErrorOnlyDrain") { [weak self, weak pass] in
            guard let pass else { return }
            self?.suspend(pass)
        }
        send(pass)
    }

    private func send(_ pass: Pass) {
        guard self.pass === pass else { return }
        guard let metadata = buffer.metadata(of: pass.sessionId) else {
            finish(pass)
            return
        }
        if isExpired(metadata) {
            Log.w("[ErrorOnlyDrain] giving up on the held events of session \(pass.sessionId)")
            buffer.remove(pass.sessionId)
            finish(pass)
            return
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
        // A trigger or a delivered request the disk does not record yet: sending on could send it
        // again after a restart, or lose the session to cleanup. Retried on the failure slots,
        // without counting.
        guard buffer.ensureMetadataSaved(of: pass.sessionId) else {
            pass.anchor = pass.anchor ?? now
            retry(pass, after: now)
            return
        }
        guard let chunk = buffer.nextChunk(of: pass.sessionId,
                                           maxEvents: Self.maxEventsPerRequest,
                                           maxBytes: Self.maxBytesPerRequest) else {
            finish(pass)
            return
        }
        // Every line of a chunk could be unreadable; it is consumed all the same.
        let result = chunk.events.isEmpty ? .delivered : upload(chunk.events)
        answered(result, for: chunk, sentAt: now, in: pass)
    }

    private func answered(_ result: SpanUploadResult, for chunk: ErrorOnlyBuffer.Chunk, sentAt: Date, in pass: Pass) {
        let answeredAt = clock.now()
        if let retryAfter = result.retryAfter {
            holdUntil = max(holdUntil ?? .distantPast, answeredAt.addingTimeInterval(retryAfter))
        }
        switch result.disposition {
        case .delivered, .permanentReject:
            buffer.commit(chunk)
            pass.anchor = nil
            wait(pass, until: max(answeredAt.addingTimeInterval(Self.gapBetweenRequests), holdUntil ?? .distantPast),
                 bounded: false)
        case .retryable:
            if result.countsAsFailedUpload {
                buffer.countFailedUpload(of: pass.sessionId)
            }
            pass.anchor = pass.anchor ?? sentAt
            retry(pass, after: answeredAt)
        case .notAttempted:
            end(pass)
        }
    }

    /// Waits for the first stored-crash retry slot still ahead, or for `Retry-After` if later.
    private func retry(_ pass: Pass, after answeredAt: Date) {
        guard let anchor = pass.anchor,
              let slot = CrashDeliveryScheduler.retrySlots.map({ anchor.addingTimeInterval($0) })
                .first(where: { $0 > answeredAt }) else {
            end(pass)
            return
        }
        wait(pass, until: max(slot, holdUntil ?? slot))
    }

    /// Resumes the pass at `date`. While retrying, a date past the last retry slot ends the pass.
    private func wait(_ pass: Pass, until date: Date, bounded: Bool = true) {
        if bounded, let anchor = pass.anchor,
           date > anchor.addingTimeInterval(CrashDeliveryScheduler.lastSlot) {
            end(pass)
            return
        }
        pass.timer = clock.schedule(at: date) { [weak self] in
            self?.enqueue { self?.send(pass) }
        }
    }

    /// The session's buffer is done with; the next session goes.
    private func finish(_ pass: Pass) {
        end(pass)
        runNext()
    }

    /// Ends the pass and leaves what is left of the buffer on disk.
    private func end(_ pass: Pass) {
        guard self.pass === pass else { return }
        self.pass = nil
        pass.timer?.cancel()
        pass.task?.end()
    }

    private func isExpired(_ metadata: ErrorOnlyBuffer.Metadata) -> Bool {
        metadata.failedUploads >= CrashDeliveryScheduler.maxFailedUploads
            || clock.now().timeIntervalSince(metadata.createdAt) > CrashDeliveryScheduler.maxAge
    }
}
