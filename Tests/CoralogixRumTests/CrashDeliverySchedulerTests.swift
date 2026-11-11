//
//  CrashDeliverySchedulerTests.swift
//
//  Stored crashes are sent one at a time, back to back until one fails; the pass then retries
//  at +30 s and +2 min from the first send of the first crash that failed, honours Retry-After,
//  and leaves the rest for the next launch. Driven by a clock the test moves, with no sleeps.
//

import XCTest
import CoralogixInternal

@testable import Coralogix

/// Answers each send as `reply` says and records when it was asked.
private final class ScriptedSender: StoredCrashSending {
    enum Reply {
        case now(CrashUploadAnswer)
        case after(TimeInterval, CrashUploadAnswer)
        case never
    }

    private let clock: ManualDeliveryClock
    private let lock = NSLock()
    var reply: (_ crashId: String, _ attempt: Int) -> Reply = { _, _ in .now(.init(outcome: .delivered)) }
    private(set) var sends: [(crashId: String, at: TimeInterval)] = []
    private(set) var cancels = 0
    private var pendingCompletion: ((CrashUploadAnswer) -> Void)?
    let start: Date

    init(clock: ManualDeliveryClock) {
        self.clock = clock
        self.start = clock.now()
    }

    func sendStoredCrash(_ item: CrashDeliveryScheduler.Item, as record: StoredCrashRecord,
                         completion: @escaping (CrashUploadAnswer) -> Void) {
        lock.lock()
        sends.append((item.crashId, clock.now().timeIntervalSince(start)))
        let attempt = sends.filter { $0.crashId == item.crashId }.count
        pendingCompletion = completion
        lock.unlock()
        switch reply(item.crashId, attempt) {
        case .now(let answer):
            completion(answer)
        case .after(let delay, let answer):
            _ = clock.schedule(at: clock.now().addingTimeInterval(delay)) { completion(answer) }
        case .never:
            break
        }
    }

    func cancelStoredCrashSend() {
        lock.lock()
        cancels += 1
        let completion = pendingCompletion
        lock.unlock()
        completion?(.init(outcome: .notAttempted))
    }

    func times(of crashId: String) -> [TimeInterval] {
        sends.filter { $0.crashId == crashId }.map(\.at)
    }
}

private let serverError = CrashUploadAnswer(outcome: .failed(counted: true))

final class CrashDeliverySchedulerTests: XCTestCase {

    private let crashTime = Date(timeIntervalSince1970: 1_700_000_000)
    private var clock: ManualDeliveryClock!
    private var store: CrashDeliveryStore!
    private var sender: ScriptedSender!
    private var tasks: FakeBackgroundTasks!
    private var online = true
    private var scheduler: CrashDeliveryScheduler!
    private var passEnded = false

    override func setUp() {
        super.setUp()
        clock = ManualDeliveryClock(start: crashTime.addingTimeInterval(60))
        store = .temporary()
        sender = ScriptedSender(clock: clock)
        tasks = FakeBackgroundTasks()
        online = true
        passEnded = false
        scheduler = CrashDeliveryScheduler(store: store, sender: sender, clock: clock, backgroundTasks: tasks,
                                           isOnline: { [unowned self] in self.online })
    }

    override func tearDown() {
        scheduler.stop()
        scheduler.waitUntilSettled()
        super.tearDown()
    }

    /// Stores crashes with these ids, newest first, each with a copy on disk.
    @discardableResult
    private func storeCrashes(_ ids: [String], crashTime: Date? = nil, failedUploads: Int = 0) throws -> [CrashDeliveryScheduler.Item] {
        try FileManager.default.createDirectory(at: store.copiesDirectory, withIntermediateDirectories: true)
        return try ids.map { id in
            store.save(.fixture(crashId: id, crashTime: crashTime ?? self.crashTime, failedUploads: failedUploads))
            let copy = store.copiesDirectory.appendingPathComponent("\(id).plcrash")
            try Data("report".utf8).write(to: copy)
            return .init(crashId: id, copy: copy)
        }
    }

    private func isStored(_ id: String) -> Bool {
        store.record(for: id) != nil && store.copies().contains { $0.lastPathComponent == "\(id).plcrash" }
    }

    /// Starts the pass, then lets time run until nothing is scheduled.
    private func deliver(_ items: [CrashDeliveryScheduler.Item]) {
        scheduler.start(items) { [unowned self] in self.passEnded = true }
        runClock()
    }

    private func runClock() {
        scheduler.waitUntilSettled()
        while let next = clock.nextDate {
            clock.advance(to: next)
            scheduler.waitUntilSettled()
        }
    }

    // MARK: - Slots

    func test_aServerError_isSentAt0_30_and120Seconds_thenKept() throws {
        let items = try storeCrashes(["A"])
        sender.reply = { _, _ in .now(serverError) }

        deliver(items)

        XCTAssertEqual(sender.times(of: "A"), [0, 30, 120])
        XCTAssertEqual(store.record(for: "A")?.failedUploads, 3)
        XCTAssertTrue(isStored("A"), "left for the next launch")
        XCTAssertTrue(passEnded)
    }

    func test_aDeliveredOrRejectedCrash_isSentOnce_andDeleted() throws {
        let items = try storeCrashes(["delivered", "rejected"])
        sender.reply = { id, _ in .now(.init(outcome: id == "delivered" ? .delivered : .rejected)) }

        deliver(items)

        XCTAssertEqual(sender.sends.map(\.crashId), ["delivered", "rejected"])
        XCTAssertEqual(sender.sends.map(\.at), [0, 0], "back to back")
        XCTAssertFalse(isStored("delivered"))
        XCTAssertFalse(isStored("rejected"))
    }

    func test_aCrashBehindAFailingOne_waitsForTheSlot_thenBothGoBackToBack() throws {
        let items = try storeCrashes(["A", "B"])
        sender.reply = { id, attempt in .now(id == "A" && attempt == 1 ? serverError : .init(outcome: .delivered)) }

        deliver(items)

        XCTAssertEqual(sender.sends.map(\.crashId), ["A", "A", "B"])
        XCTAssertEqual(sender.sends.map(\.at), [0, 30, 30])
        XCTAssertFalse(isStored("A"))
        XCTAssertFalse(isStored("B"))
    }

    func test_anAnswerAfterTheFirstSlot_skipsIt() throws {
        let items = try storeCrashes(["A"])
        sender.reply = { _, attempt in attempt == 1 ? .after(40, serverError) : .now(.init(outcome: .delivered)) }

        deliver(items)

        XCTAssertEqual(sender.times(of: "A"), [0, 120])
    }

    // MARK: - Retry-After

    func test_retryAfter_movesTheNextSendLater_thanTheSlot_butNotToTheNextOne() throws {
        let items = try storeCrashes(["A"])
        sender.reply = { _, attempt in
            .now(attempt == 1 ? .init(outcome: .failed(counted: true), retryAfter: 60) : .init(outcome: .delivered))
        }

        deliver(items)

        XCTAssertEqual(sender.times(of: "A"), [0, 60])
    }

    func test_retryAfter_holdsBackTheNextCrashToo() throws {
        let items = try storeCrashes(["A", "B"])
        sender.reply = { id, attempt in
            switch (id, attempt) {
            case ("A", 1): return .now(.init(outcome: .failed(counted: true), retryAfter: 100))
            case ("A", _): return .now(.init(outcome: .rejected, retryAfter: 15))
            default: return .now(.init(outcome: .delivered))
            }
        }

        deliver(items)

        XCTAssertEqual(sender.times(of: "A"), [0, 100])
        XCTAssertEqual(sender.times(of: "B"), [115], "held back by the Retry-After of A's answer")
    }

    func test_retryAfterPastTheLastSlot_endsThePass() throws {
        let items = try storeCrashes(["A"])
        sender.reply = { _, _ in .now(.init(outcome: .failed(counted: true), retryAfter: 300)) }

        deliver(items)

        XCTAssertEqual(sender.times(of: "A"), [0])
        XCTAssertTrue(isStored("A"))
        XCTAssertTrue(passEnded)
    }

    // MARK: - Not attempted, no answer, offline

    func test_notAttemptedWhileOnline_movesOn_withoutRetryingThisLaunch() throws {
        let items = try storeCrashes(["A", "B"])
        sender.reply = { id, _ in .now(.init(outcome: id == "A" ? .notAttempted : .delivered)) }

        deliver(items)

        XCTAssertEqual(sender.sends.map(\.crashId), ["A", "B"])
        XCTAssertTrue(isStored("A"))
        XCTAssertEqual(store.record(for: "A")?.failedUploads, 0)
        XCTAssertFalse(isStored("B"))
    }

    func test_notAttemptedWhileOffline_endsThePass() throws {
        let items = try storeCrashes(["A", "B"])
        sender.reply = { [unowned self] _, _ in
            self.online = false
            return .now(.init(outcome: .notAttempted))
        }

        deliver(items)

        XCTAssertEqual(sender.sends.map(\.crashId), ["A"])
        XCTAssertTrue(isStored("B"))
    }

    func test_noAnswerIn130Seconds_endsThePass() throws {
        let items = try storeCrashes(["A", "B"])
        sender.reply = { _, _ in .never }

        scheduler.start(items) { [unowned self] in self.passEnded = true }
        scheduler.waitUntilSettled()
        clock.advance(to: sender.start.addingTimeInterval(129))
        scheduler.waitUntilSettled()
        XCTAssertFalse(passEnded)

        clock.advance(to: sender.start.addingTimeInterval(130))
        scheduler.waitUntilSettled()

        XCTAssertTrue(passEnded)
        XCTAssertEqual(sender.sends.map(\.crashId), ["A"])
        XCTAssertTrue(isStored("A"))
        XCTAssertTrue(isStored("B"))
    }

    func test_offline_sendsNothing() throws {
        let items = try storeCrashes(["A"])
        online = false

        deliver(items)

        XCTAssertTrue(sender.sends.isEmpty)
        XCTAssertTrue(isStored("A"))
        XCTAssertTrue(passEnded)
    }

    // MARK: - Expiry

    func test_after16CountedFailures_theCrashIsDeleted_withoutA17thSend() throws {
        let items = try storeCrashes(["A"], failedUploads: 15)
        sender.reply = { _, _ in .now(serverError) }

        deliver(items)

        XCTAssertEqual(sender.times(of: "A"), [0])
        XCTAssertFalse(isStored("A"))
    }

    func test_anUncountedFailure_doesNotUseUpAnAttempt() throws {
        let items = try storeCrashes(["A"], failedUploads: 15)
        sender.reply = { _, _ in .now(.init(outcome: .failed(counted: false))) }

        deliver(items)

        XCTAssertEqual(sender.times(of: "A"), [0, 30, 120])
        XCTAssertEqual(store.record(for: "A")?.failedUploads, 15)
    }

    func test_aCrashOlderThan7Days_isDeleted_unsent() throws {
        let day: TimeInterval = 24 * 60 * 60
        clock = ManualDeliveryClock(start: crashTime.addingTimeInterval(8 * day))
        setUpScheduler()
        let old = try storeCrashes(["old"])

        deliver(old)

        XCTAssertTrue(sender.sends.isEmpty)
        XCTAssertFalse(isStored("old"))
    }

    func test_aCrash3DaysOld_orFromTheFuture_isSent() throws {
        let day: TimeInterval = 24 * 60 * 60
        clock = ManualDeliveryClock(start: crashTime.addingTimeInterval(3 * day))
        setUpScheduler()
        let items = try storeCrashes(["recent"]) + storeCrashes(["future"], crashTime: crashTime.addingTimeInterval(30 * day))

        deliver(items)

        XCTAssertEqual(sender.sends.map(\.crashId), ["recent", "future"])
    }

    private func setUpScheduler() {
        sender = ScriptedSender(clock: clock)
        scheduler = CrashDeliveryScheduler(store: store, sender: sender, clock: clock, backgroundTasks: tasks,
                                           isOnline: { [unowned self] in self.online })
    }

    // MARK: - Background time

    func test_thePass_holdsBackgroundTime_andEndsItOnce() throws {
        let items = try storeCrashes(["A"])

        deliver(items)

        XCTAssertEqual(tasks.begun, 1)
        XCTAssertEqual(tasks.ended, 1)
    }

    func test_whenBackgroundTimeRunsOut_theSendIsCancelled_andNothingCounted() throws {
        let items = try storeCrashes(["A", "B"])
        sender.reply = { _, _ in .never }
        scheduler.start(items) { [unowned self] in self.passEnded = true }
        scheduler.waitUntilSettled()

        tasks.expireAll()
        scheduler.waitUntilSettled()

        XCTAssertEqual(sender.cancels, 1)
        XCTAssertTrue(passEnded)
        XCTAssertEqual(tasks.ended, 1, "ended once, by the expiration")
        XCTAssertEqual(sender.sends.map(\.crashId), ["A"], "the pass does not go on to B")
        XCTAssertTrue(isStored("A"))
        XCTAssertEqual(store.record(for: "A")?.failedUploads, 0)
        runClock()
        XCTAssertEqual(sender.sends.count, 1, "and does not come back")
    }

    func test_start_doesNotBlock() throws {
        let items = try storeCrashes(["A"])
        let sending = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        sender.reply = { _, _ in
            sending.signal()
            release.wait()
            return .now(.init(outcome: .delivered))
        }

        scheduler.start(items)
        XCTAssertEqual(sending.wait(timeout: .now() + 5), .success, "the send runs on the scheduler's own queue")
        release.signal()
        scheduler.waitUntilSettled()
        XCTAssertFalse(isStored("A"))
    }
}
