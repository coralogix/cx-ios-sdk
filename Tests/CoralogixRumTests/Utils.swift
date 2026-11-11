//
//  MockSpanData.swift
//  
//
//  Created by Coralogix DEV TEAM on 08/05/2024.
//

import Foundation

@testable import Coralogix

class MockSpanData: SpanDataProtocol {
    var attributes: [String: Any] = [:]
    var status: String?
    var traceId: String?
    var spanId: String?
    var startTime: TimeInterval
    var endTime: TimeInterval
    var statusCode: [String: Any] = [:]
    var name: String?
    var resources: [String: Any] = [:]
    var kind: Int
    var statusText: String?
    
    func getStatus() -> String? {
        return self.status
    }
    
    func getEndTime() -> TimeInterval? {
        return self.endTime
    }
    
    func getStartTime() -> TimeInterval? {
        return self.startTime
    }
    
    func getTraceId() -> String? {
        return self.traceId
    }
    
    func getSpanId() -> String? {
        return self.spanId
    }
    
    func getParentSpanId() -> String? {
        return nil
    }
    
    func getAttribute(forKey: String) -> Any? {
        let attribute = attributes[forKey] as? AttributeValue
        return attribute?.description
    }
    
    func getStatusCode() -> [String : Any] {
        return self.statusCode
    }
    
    func getAttributes() -> [String : Any]? {
        return self.attributes
    }
    
    func getName() -> String? {
        return self.name
    }
    
    func getKind() -> Int {
        return self.kind
    }
    
    func getResources() -> [String : Any] {
        return self.resources
    }
    
    func getStatusText() -> String {
        return self.statusText ?? ""
    }

    // Add initializer or other methods to set up the mock data as needed
    init(attributes: [String: Any], 
         status: String? = nil,
         startTime: Date? = nil,
         endTime: Date? = nil,
         spanId: String? = nil,
         traceId: String? = nil,
         name: String? = nil,
         kind: Int = 0,
         statusText: String? = nil,
         statusCode: [String: Any]? = nil,
         resources: [String: Any]? = nil) {
        self.attributes = attributes
        self.status = status
        self.endTime = endTime?.timeIntervalSince1970 ?? 0
        self.startTime = startTime?.timeIntervalSince1970 ?? 0
        self.traceId = traceId
        self.spanId = spanId
        self.kind = kind
        self.name = name
        self.statusText = statusText
        self.traceId = traceId
        self.statusCode = statusCode ?? [:]
        self.resources = resources ?? [:]
    }
}

class MockKeyschainManager: KeyChainProtocol {
    var pid = ""
    var sessionId = ""
    var sessionTimeInterval = ""
    /// nil (unlike the "" sentinels above) so tests can distinguish "never written"
    /// from "written empty" — loadPrevSession treats absence as a legacy launch.
    var sessionSampledIn: String?

    func readStringFromKeychain(service: String, key: String) -> String? {
        if key == "pid" {
            return self.pid
        } else if key == "sessionId" {
            return self.sessionId
        } else if key == "sessionTimeInterval" {
            return self.sessionTimeInterval
        } else if key == "sessionSampledIn" {
            return self.sessionSampledIn
        }
        return nil
    }

    func writeStringToKeychain(service: String, key: String, value: String) {
        if key == "pid" {
            self.pid = value
        } else if key == "sessionId" {
            self.sessionId = value
        } else if key == "sessionTimeInterval" {
            self.sessionTimeInterval = value
        } else if key == "sessionSampledIn" {
            self.sessionSampledIn = value
        }
    }

    func deleteFromKeychain(service: String, key: String) {
        if key == "pid" {
            self.pid = ""
        } else if key == "sessionId" {
            self.sessionId = ""
        } else if key == "sessionTimeInterval" {
            self.sessionTimeInterval = ""
        } else if key == "sessionSampledIn" {
            self.sessionSampledIn = nil
        }
    }
}

class MockNetworkManager: NetworkProtocol {
    func getNetworkType() -> String {
        return "5G"
    }
}

extension SessionManager {
    /// Makes `sessionId` the live session — the one every span the SDK stamps itself carries.
    @discardableResult
    func makeLive(sessionId: String = "session_001") -> Self {
        sessionMetadata = SessionMetadata(sessionId: sessionId,
                                          sessionCreationDate: Date().timeIntervalSince1970,
                                          using: MockKeyChain())
        return self
    }
}

extension SessionSnapshotStore {
    /// A directory of session records of its own, as an app's fresh install has.
    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SessionSnapshots-\(UUID().uuidString)", isDirectory: true)
    }

    /// A store over records no other test sees, as launch `launchId` reads them.
    static func temporary(directory: URL = temporaryDirectory(),
                          launchId: String = "this-launch",
                          keychain: MockKeyChain = MockKeyChain(),
                          now: Date = Date()) -> SessionSnapshotStore {
        SessionSnapshotStore(keychain: keychain, directory: directory, launchId: launchId, now: now)
    }

    /// The store as the launch after one that persisted `record` sees it.
    static func relaunched(after record: SessionSnapshotRecord?,
                           directory: URL = temporaryDirectory()) -> SessionSnapshotStore {
        if let record {
            temporary(directory: directory, launchId: "previous-launch").persist(record)
        }
        return temporary(directory: directory, launchId: "relaunch")
    }
}

extension StoredCrashRecord {
    /// A stored crash of session `sessionId` whose counters are `counters`.
    static func fixture(crashId: String = "crash-id",
                        sessionId: String = "crashed",
                        sampledIn: Bool? = true,
                        crashTime: Date = Date(timeIntervalSince1970: 1_700_000_000),
                        failedUploads: Int = 0,
                        counters: SessionSnapshotRecord? = nil) -> StoredCrashRecord {
        StoredCrashRecord(crashId: crashId,
                          kind: .native,
                          crashTime: crashTime,
                          failedUploads: failedUploads,
                          session: .init(id: sessionId, creationDate: 1_699_999_000, sampledIn: sampledIn),
                          counters: counters ?? SessionSnapshotRecord(sessionId: sessionId, errorCount: 0, viewCount: 0,
                                                                      actionCount: 0, hasRecording: false))
    }
}

extension CrashDeliveryStore {
    /// A store in a directory of its own, so a test never touches the app's real crash files.
    static func temporary() -> CrashDeliveryStore {
        CrashDeliveryStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("CrashDeliveryStore-\(UUID().uuidString)", isDirectory: true))
    }
}

/// A clock that moves only when a test moves it.
final class ManualDeliveryClock: DeliveryClock {
    private let lock = NSLock()
    private var current: Date
    private var pending: [(date: Date, timer: DeliveryTimer, work: () -> Void)] = []

    init(start: Date = Date()) {
        self.current = start
    }

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func schedule(at date: Date, _ work: @escaping () -> Void) -> DeliveryTimer {
        let timer = DeliveryTimer()
        lock.lock(); defer { lock.unlock() }
        pending.append((date, timer, work))
        return timer
    }

    /// When the next timer still armed fires.
    var nextDate: Date? {
        lock.lock(); defer { lock.unlock() }
        return pending.filter { !$0.timer.isCancelled }.map(\.date).min()
    }

    /// Fires, in order, every timer due by `date`.
    func advance(to date: Date) {
        while true {
            lock.lock()
            pending.removeAll { $0.timer.isCancelled }
            guard let index = pending.indices.filter({ pending[$0].date <= date })
                .min(by: { pending[$0].date < pending[$1].date }) else {
                current = max(current, date)
                lock.unlock()
                return
            }
            let due = pending.remove(at: index)
            current = max(current, due.date)
            lock.unlock()
            due.work()
        }
    }
}

/// Background tasks that never expire on their own; a test expires them.
final class FakeBackgroundTasks: BackgroundTaskRunning {
    private let lock = NSLock()
    private var expirations: [() -> Void] = []
    private(set) var begun = 0
    private(set) var ended = 0

    func begin(name: String, expiration: @escaping () -> Void) -> BackgroundTask {
        lock.lock(); defer { lock.unlock() }
        begun += 1
        let task = BackgroundTask { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); self.ended += 1; self.lock.unlock()
        }
        expirations.append { expiration(); task.end() }
        return task
    }

    /// The system taking the background time back.
    func expireAll() {
        lock.lock()
        let all = expirations
        expirations = []
        lock.unlock()
        all.forEach { $0() }
    }
}
