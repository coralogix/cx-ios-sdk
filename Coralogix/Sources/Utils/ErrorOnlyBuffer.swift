//
//  ErrorOnlyBuffer.swift
//  Coralogix
//

import Foundation
import CoralogixInternal

/// Appends bytes to a file, and cuts a file back to a length. A protocol so tests can make a
/// write fail the way a full disk does.
protocol ErrorOnlyFileWriting {
    func append(_ data: Data, to url: URL) throws
    func truncate(_ url: URL, to length: UInt64)
}

/// POSIX calls, because `FileHandle.write(_:)` raises an Objective-C exception on a full disk and
/// its throwing replacement needs iOS 13.4.
struct PosixFileWriter: ErrorOnlyFileWriting {
    func append(_ data: Data, to url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_APPEND)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                guard let base = buffer.baseAddress else { return }
                let written = write(descriptor, base.advanced(by: offset), buffer.count - offset)
                guard written > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += written
            }
        }
    }

    func truncate(_ url: URL, to length: UInt64) {
        _ = Darwin.truncate(url.path, off_t(length))
    }
}

/// The events of sessions held until an error (`SessionMode.errorOnly`), one session per pair of
/// files: `<session>.jsonl`, one final encoded event per line, and `<session>.meta.json`, whether
/// the session has had its error and how far its delivery got.
///
/// Holds final events — after URL masking and every `beforeSend` — so draining never needs the
/// customer's callbacks again. Disk is the buffer so that a crash, sent on the next launch, still
/// finds the events that came before it; memory stays flat however many events a session holds.
///
/// Best effort: a write that fails is cut back to the last whole event and the rest of the session
/// is held in memory, within smaller caps. Passing any cap before an error clears the session's
/// buffer, as the browser SDK clears its cache past `maxRumEvents`.
final class ErrorOnlyBuffer {
    static let maxEventBytes = 1_024 * 1_024
    static let maxBufferBytes = 50 * 1_024 * 1_024
    static let bytesPerEvent = 4 * 1_024
    static let maxMemoryEvents = 1_000
    static let maxMemoryBytes = 4 * 1_024 * 1_024
    /// Sessions that had their error, remembered so their later events are sent as they happen.
    static let triggeredSessionsKept = 32

    private static let eventsExtension = "jsonl"
    private static let metadataSuffix = ".meta.json"
    private static let newline = Data([0x0A])

    struct Metadata: Codable, Equatable {
        let sessionId: String
        /// The buffer instance that wrote it: another one's file is a leftover of an earlier launch
        /// or SDK instance.
        let owner: String
        let createdAt: Date
        var triggered: Bool
        /// Bytes of the events file already delivered or refused for good.
        var sentOffset: UInt64
        var failedUploads: Int
    }

    /// Up to one request of a session's events, oldest first.
    struct Chunk {
        let sessionId: String
        let events: [[String: Any]]
        /// Where the file's next unsent event starts once this chunk is done; nil for a chunk of
        /// the in-memory part.
        let fileEndOffset: UInt64?
        let memoryCount: Int
    }

    private struct Session {
        var metadata: Metadata
        var eventCount = 0
        var byteCount = 0
        /// Set once a write failed: the rest of the session is held in memory.
        var diskFailed = false
        var memory: [Data] = []
        var memoryBytes = 0
    }

    #if DEBUG
    /// Tests only: where an SDK instance keeps its buffers instead of the app's folder. Not
    /// compiled in Release.
    static var testDirectory: URL?
    #endif

    static var defaultDirectory: URL {
        #if DEBUG
        if let testDirectory { return testDirectory }
        #endif
        return CrashDeliveryStore.defaultFolder.appendingPathComponent("error-only", isDirectory: true)
    }

    let directory: URL
    let maxEvents: Int
    let maxBytes: Int
    let owner = UUID().uuidString.lowercased()
    private let writer: ErrorOnlyFileWriting
    private let lock = NSLock()
    private var sessions: [String: Session] = [:]
    /// Oldest first, capped at `triggeredSessionsKept`.
    private var triggeredSessionIds: [String] = []

    init(maxRumEvents: Int,
         directory: URL = ErrorOnlyBuffer.defaultDirectory,
         writer: ErrorOnlyFileWriting = PosixFileWriter()) {
        self.directory = directory
        self.maxEvents = maxRumEvents
        self.maxBytes = min(maxRumEvents * Self.bytesPerEvent, Self.maxBufferBytes)
        self.writer = writer
    }

    // MARK: - Holding

    /// Holds one final event of `sessionId`. Returns false, holding nothing, when the session has
    /// had its error in the meantime: the event is then sent as it happens.
    @discardableResult
    func hold(_ event: Data, sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !triggeredSessionIds.contains(sessionId) else { return false }
        guard event.count <= Self.maxEventBytes else {
            Log.e("[ErrorOnlyBuffer] an event of \(event.count) bytes is over the 1 MB limit — dropped")
            return true
        }
        var session = sessions[sessionId] ?? Session(metadata: Metadata(sessionId: sessionId, owner: owner,
                                                                        createdAt: Date(), triggered: false,
                                                                        sentOffset: 0, failedUploads: 0))
        if !session.diskFailed && !appendLocked(event, to: &session) {
            session.diskFailed = true
        }
        if session.diskFailed {
            session.memory.append(event)
            session.memoryBytes += event.count
        }
        session.eventCount += 1
        session.byteCount += event.count + 1

        let overflowed = session.eventCount > maxEvents
            || session.byteCount > maxBytes
            || session.memory.count > Self.maxMemoryEvents
            || session.memoryBytes > Self.maxMemoryBytes
        guard !overflowed else {
            Log.d("[ErrorOnlyBuffer] session \(sessionId) held more than its cap before an error — cleared")
            removeLocked(sessionId)
            return true
        }
        sessions[sessionId] = session
        return true
    }

    /// Returns whether the write reached disk. A failed one is cut back to the last whole event.
    private func appendLocked(_ event: Data, to session: inout Session) -> Bool {
        let fileURL = eventsURL(of: session.metadata.sessionId)
        var length: UInt64 = 0
        do {
            if session.eventCount == 0 || !FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Self.write(Data(), to: fileURL)
                try writeMetadataLocked(session.metadata)
            }
            length = Self.fileSize(of: fileURL)
            try writer.append(event + Self.newline, to: fileURL)
            return true
        } catch {
            writer.truncate(fileURL, to: length)
            Log.e("[ErrorOnlyBuffer] could not write a held event (\(error)) — holding the rest of session \(session.metadata.sessionId) in memory")
            return false
        }
    }

    // MARK: - Trigger

    func isTriggered(_ sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return triggeredSessionIds.contains(sessionId)
    }

    /// Records that `sessionId` had its error. Returns whether it has held events to drain.
    @discardableResult
    func trigger(_ sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if !triggeredSessionIds.contains(sessionId) {
            triggeredSessionIds.append(sessionId)
            if triggeredSessionIds.count > Self.triggeredSessionsKept {
                triggeredSessionIds.removeFirst(triggeredSessionIds.count - Self.triggeredSessionsKept)
            }
        }
        guard var session = sessions[sessionId] else { return false }
        session.metadata.triggered = true
        sessions[sessionId] = session
        // Persisted so a drain cut short resumes on the next launch instead of being taken for a
        // session that ended without an error.
        try? writeMetadataLocked(session.metadata)
        return true
    }

    /// Deletes what `sessionId` held, unless it had its error: its drain still needs it.
    func discardUntriggered(_ sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let session = sessions[sessionId], !session.metadata.triggered else { return }
        removeLocked(sessionId)
    }

    /// Deletes every session this instance holds that has not had its error.
    func discardAllUntriggered() {
        lock.lock()
        defer { lock.unlock() }
        for (id, session) in sessions where !session.metadata.triggered {
            removeLocked(id)
        }
    }

    // MARK: - Draining

    func metadata(of sessionId: String) -> Metadata? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[sessionId]?.metadata
    }

    /// Sessions with a triggered buffer still to send.
    func triggeredSessions() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return sessions.values.filter(\.metadata.triggered).sorted { $0.metadata.createdAt < $1.metadata.createdAt }
            .map(\.metadata.sessionId)
    }

    /// The next request of `sessionId`'s events, oldest first: whole events only, at most
    /// `maxEvents` of them and `maxBytes` in all. The file comes first, then what is held in
    /// memory. nil when nothing is left, in which case the session's files are deleted.
    func nextChunk(of sessionId: String, maxEvents: Int, maxBytes: Int) -> Chunk? {
        lock.lock()
        defer { lock.unlock() }
        guard let session = sessions[sessionId] else { return nil }
        if let chunk = fileChunkLocked(session, maxEvents: maxEvents, maxBytes: maxBytes) {
            return chunk
        }
        var taken = 0
        var bytes = 0
        for line in session.memory {
            guard taken < maxEvents, bytes + line.count <= maxBytes else { break }
            bytes += line.count
            taken += 1
        }
        guard taken > 0 else {
            removeLocked(sessionId)
            return nil
        }
        return Chunk(sessionId: sessionId, events: session.memory.prefix(taken).compactMap(Self.decode),
                     fileEndOffset: nil, memoryCount: taken)
    }

    /// A missing or short file is a normal case (the OS may purge the folder): what is there goes.
    private func fileChunkLocked(_ session: Session, maxEvents: Int, maxBytes: Int) -> Chunk? {
        let fileURL = eventsURL(of: session.metadata.sessionId)
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return nil }
        let start = Int(session.metadata.sentOffset)
        guard start < data.count else { return nil }
        let window = data[start..<min(data.count, start + maxBytes + 1)]
        var events: [[String: Any]] = []
        var consumed = 0
        var lineStart = window.startIndex
        while events.count < maxEvents, let newline = window[lineStart...].firstIndex(of: 0x0A) {
            let line = window[lineStart..<newline]
            guard consumed + line.count <= maxBytes || consumed == 0 else { break }
            consumed += line.count + 1
            if let event = Self.decode(Data(line)) { events.append(event) }
            lineStart = window.index(after: newline)
        }
        guard consumed > 0 else { return nil }
        return Chunk(sessionId: session.metadata.sessionId, events: events,
                     fileEndOffset: session.metadata.sentOffset + UInt64(consumed), memoryCount: 0)
    }

    /// The chunk was delivered or refused for good: it is never sent again.
    func commit(_ chunk: Chunk) {
        lock.lock()
        defer { lock.unlock() }
        guard var session = sessions[chunk.sessionId] else { return }
        if let end = chunk.fileEndOffset {
            session.metadata.sentOffset = end
            try? writeMetadataLocked(session.metadata)
        } else {
            let removed = session.memory.prefix(chunk.memoryCount)
            session.memoryBytes -= removed.reduce(0) { $0 + $1.count }
            session.memory.removeFirst(min(chunk.memoryCount, session.memory.count))
        }
        sessions[chunk.sessionId] = session
    }

    /// Counts one failed request of `sessionId`'s drain toward its limit.
    func countFailedUpload(of sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var session = sessions[sessionId] else { return }
        session.metadata.failedUploads += 1
        sessions[sessionId] = session
        try? writeMetadataLocked(session.metadata)
    }

    func remove(_ sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        removeLocked(sessionId)
    }

    // MARK: - Earlier launches

    /// Adopts what earlier launches (or SDK instances) left: `keep` decides, from its metadata,
    /// whether a leftover is kept; the rest is deleted. Returns the kept ones that already had
    /// their error, oldest first, to drain now.
    func adoptLeftovers(keep: (Metadata) -> Bool) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var adopted: [Metadata] = []
        for url in files where url.lastPathComponent.hasSuffix(Self.metadataSuffix) {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let metadata = try? JSONDecoder().decode(Metadata.self, from: data) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            guard metadata.owner != owner, sessions[metadata.sessionId] == nil else { continue }
            guard keep(metadata), FileManager.default.fileExists(atPath: eventsURL(of: metadata.sessionId).path) else {
                deleteFilesLocked(metadata.sessionId)
                continue
            }
            sessions[metadata.sessionId] = Session(metadata: metadata)
            adopted.append(metadata)
        }
        // Events files whose metadata is gone can never be attributed.
        for url in files where url.pathExtension == Self.eventsExtension {
            let id = url.deletingPathExtension().lastPathComponent
            if sessions[id] == nil && !FileManager.default.fileExists(atPath: metadataURL(of: id).path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return adopted.filter(\.triggered).sorted { $0.createdAt < $1.createdAt }.map(\.sessionId)
    }

    // MARK: - Files

    private func removeLocked(_ sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        deleteFilesLocked(sessionId)
    }

    private func deleteFilesLocked(_ sessionId: String) {
        try? FileManager.default.removeItem(at: eventsURL(of: sessionId))
        try? FileManager.default.removeItem(at: metadataURL(of: sessionId))
    }

    private func writeMetadataLocked(_ metadata: Metadata) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.write(JSONEncoder().encode(metadata), to: metadataURL(of: metadata.sessionId))
    }

    /// Readable from the first unlock on, like the crash store's files.
    private static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func fileSize(of url: URL) -> UInt64 {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        return size?.uint64Value ?? 0
    }

    private static func decode(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    private func eventsURL(of sessionId: String) -> URL {
        directory.appendingPathComponent(Self.fileName(sessionId)).appendingPathExtension(Self.eventsExtension)
    }

    private func metadataURL(of sessionId: String) -> URL {
        directory.appendingPathComponent(Self.fileName(sessionId) + Self.metadataSuffix)
    }

    /// Session ids are UUIDs the SDK mints; anything else is kept to a safe file name.
    private static func fileName(_ sessionId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(sessionId.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
