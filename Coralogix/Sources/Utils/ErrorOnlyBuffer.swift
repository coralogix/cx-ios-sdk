//
//  ErrorOnlyBuffer.swift
//  Coralogix
//

import Foundation
import CoralogixInternal

/// Appends bytes to a file, cuts a file back to a length, and replaces a whole file. A protocol
/// so tests can make a write fail the way a full disk does.
protocol ErrorOnlyFileWriting {
    func append(_ data: Data, to url: URL) throws
    func truncate(_ url: URL, to length: UInt64)
    func replace(_ url: URL, with data: Data) throws
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

    /// Readable from the first unlock on, like the crash store's files.
    func replace(_ url: URL, with data: Data) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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
    /// Sessions that had their error, remembered so their later events are sent as they happen;
    /// and sessions whose buffer was discarded at rotation, so a late event cannot start it again.
    static let triggeredSessionsKept = 32
    static let discardedSessionsKept = 32
    /// How long an ended session that had no error keeps its buffer, as on Android: an error
    /// reported just before the session changed can still be in the batch processor or on a
    /// hybrid `beforeSend` round trip, and must still trigger it.
    static let endedSessionGrace: TimeInterval = 30

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

        /// Given up on, as a stored crash is: after 16 counted failures or 7 days.
        func isExpired(at now: Date) -> Bool {
            failedUploads >= CrashDeliveryScheduler.maxFailedUploads
                || now.timeIntervalSince(createdAt) > CrashDeliveryScheduler.maxAge
        }
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
        /// Bytes this instance has appended to the events file, so a failed write is cut back
        /// without asking the file system.
        var fileLength: UInt64 = 0
        var fileCreated = false
        /// Set while the metadata on disk is behind `metadata`.
        var metadataUnsaved = false
        /// What the disk last recorded; nil while it records nothing.
        var saved: Metadata?
        /// Set once a write failed: the rest of the session is held in memory.
        var diskFailed = false
        var memory: [Data] = []
        var memoryBytes = 0
    }

    #if DEBUG
    /// Tests only: where an SDK instance keeps its buffers instead of the app's folder, and the
    /// clock its grace periods run on. Not compiled in Release.
    static var testDirectory: URL?
    static var testClock: DeliveryClock?
    #endif

    static var defaultClock: DeliveryClock {
        #if DEBUG
        if let testClock { return testClock }
        #endif
        return SystemDeliveryClock()
    }

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
    /// Oldest first, capped at `discardedSessionsKept`.
    private var discardedSessionIds: [String] = []
    /// Ended sessions still within `endedSessionGrace`, with the timer that ends it.
    private var endingSessions: [String: DeliveryTimer] = [:]
    private let clock: DeliveryClock

    init(maxRumEvents: Int,
         directory: URL = ErrorOnlyBuffer.defaultDirectory,
         writer: ErrorOnlyFileWriting = PosixFileWriter(),
         clock: DeliveryClock = ErrorOnlyBuffer.defaultClock) {
        self.directory = directory
        self.maxEvents = maxRumEvents
        self.maxBytes = min(maxRumEvents * Self.bytesPerEvent, Self.maxBufferBytes)
        self.writer = writer
        self.clock = clock
    }

    // MARK: - Holding

    /// Holds one final event of `sessionId`. Returns false, holding nothing, when the session has
    /// had its error in the meantime: the event is then sent as it happens.
    @discardableResult
    func hold(_ event: Data, sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isTriggeredLocked(sessionId) else { return false }
        guard !discardedSessionIds.contains(sessionId) else {
            Log.d("[ErrorOnlyBuffer] event of ended session \(sessionId) held for an error — dropped")
            return true
        }
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
        do {
            if !session.fileCreated {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try writer.replace(fileURL, with: Data())
                try writeMetadataLocked(session.metadata)
                session.saved = session.metadata
                session.fileCreated = true
            }
            let line = event + Self.newline
            try writer.append(line, to: fileURL)
            session.fileLength += UInt64(line.count)
            return true
        } catch {
            writer.truncate(fileURL, to: session.fileLength)
            Log.e("[ErrorOnlyBuffer] could not write a held event (\(error)) — holding the rest of session \(session.metadata.sessionId) in memory")
            return false
        }
    }

    // MARK: - Trigger

    /// Whether `sessionId` had its error: in this process, or recorded by the launch that left its buffer.
    func isTriggered(_ sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isTriggeredLocked(sessionId)
    }

    private func isTriggeredLocked(_ sessionId: String) -> Bool {
        triggeredSessionIds.contains(sessionId) || sessions[sessionId]?.metadata.triggered == true
    }

    /// Records that `sessionId` had its error. Returns whether it has held events to drain.
    @discardableResult
    func trigger(_ sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return triggerLocked(sessionId)
    }

    /// Records that `sessionId` had its error, holding `error`, the event that is that error, as
    /// its last event: the error then goes out in the drain's requests, with what came before it,
    /// and is retried and kept across a restart like them. Returns false, holding nothing, when
    /// it could not be kept so: the caller sends it as it happens. The session has had its error
    /// either way.
    func triggerHolding(_ error: Data, sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isTriggeredLocked(sessionId) else { return false }
        let held = appendTriggerLocked(error, sessionId: sessionId)
        triggerLocked(sessionId)
        guard held, var session = sessions[sessionId] else { return false }
        guard session.metadataUnsaved else { return true }
        // On disk the session still reads as one without an error, so a restart would delete the
        // error with it: the error is taken back out and sent live.
        let line = error.count + 1
        session.fileLength -= UInt64(line)
        writer.truncate(eventsURL(of: sessionId), to: session.fileLength)
        session.eventCount -= 1
        session.byteCount -= line
        sessions[sessionId] = session
        return false
    }

    /// Appends the error that triggers `sessionId` to its events file. Past the caps on purpose:
    /// it is what the session waited for, and the session drains next.
    private func appendTriggerLocked(_ error: Data, sessionId: String) -> Bool {
        guard error.count <= Self.maxEventBytes, !discardedSessionIds.contains(sessionId) else { return false }
        let existing = sessions[sessionId]
        var session = existing ?? Session(metadata: Metadata(sessionId: sessionId, owner: owner,
                                                             createdAt: Date(), triggered: false,
                                                             sentOffset: 0, failedUploads: 0))
        // Behind what is held in memory, or in a file an earlier launch left, it would not be last.
        guard !session.diskFailed, session.metadata.owner == owner else { return false }
        guard appendLocked(error, to: &session) else {
            if existing != nil {
                session.diskFailed = true
                sessions[sessionId] = session
            }
            return false
        }
        session.eventCount += 1
        session.byteCount += error.count + 1
        sessions[sessionId] = session
        return true
    }

    @discardableResult
    private func triggerLocked(_ sessionId: String) -> Bool {
        // A session in its grace that has its error is drained like any other.
        endingSessions.removeValue(forKey: sessionId)?.cancel()
        if !triggeredSessionIds.contains(sessionId) {
            triggeredSessionIds.append(sessionId)
            if triggeredSessionIds.count > Self.triggeredSessionsKept {
                triggeredSessionIds.removeFirst(triggeredSessionIds.count - Self.triggeredSessionsKept)
            }
        }
        guard var session = sessions[sessionId] else { return false }
        session.metadata.triggered = true
        // Persisted so a drain cut short resumes on the next launch instead of being taken for a
        // session that ended without an error.
        persistMetadataLocked(&session)
        sessions[sessionId] = session
        return true
    }

    /// Whether the drain may send `sessionId`'s next request, writing its metadata again first if
    /// the disk is behind. It may unless a restart could send a request delivered now a second
    /// time: the disk records the trigger but an older cursor, and the next request comes from
    /// the file. While the disk still reads as a session without an error, a restart deletes it,
    /// so a full disk does not stop the drain; nor does a failure count it could not save. Nor
    /// does a file fully sent: `commit` already deleted it, and what comes next is from memory.
    func maySend(of sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var session = sessions[sessionId], session.metadataUnsaved else { return true }
        persistMetadataLocked(&session)
        sessions[sessionId] = session
        guard session.metadataUnsaved, let saved = session.saved, saved.triggered else { return true }
        return saved.sentOffset == session.metadata.sentOffset || isFileSentLocked(session)
    }

    /// `fileLength` counts only what this instance appended: an adopted file's length is unknown.
    private func isFileSentLocked(_ session: Session) -> Bool {
        let knowsFileLength = session.diskFailed || session.metadata.owner == owner
        return knowsFileLength && session.metadata.sentOffset >= session.fileLength
    }

    /// Writes the metadata, trying once more on failure, and records whether it reached disk.
    private func persistMetadataLocked(_ session: inout Session) {
        let hasFile = session.fileCreated || session.metadata.owner != owner
        guard hasFile else { return }
        let saved = (try? writeMetadataLocked(session.metadata)) != nil
            || (try? writeMetadataLocked(session.metadata)) != nil
        if saved {
            session.saved = session.metadata
        } else {
            Log.e("[ErrorOnlyBuffer] could not save the state of session \(session.metadata.sessionId)")
        }
        session.metadataUnsaved = !saved
    }

    /// Called when `sessionId` ends. Unless it had its error, it keeps holding for
    /// `endedSessionGrace`: a late event of it is still held, and a late error still triggers it.
    /// When the grace runs out without one, its buffer is discarded.
    func endSession(_ sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !isTriggeredLocked(sessionId), endingSessions[sessionId] == nil,
              !discardedSessionIds.contains(sessionId) else { return }
        endingSessions[sessionId] = clock.schedule(at: clock.now().addingTimeInterval(Self.endedSessionGrace)) { [weak self] in
            self?.discardUntriggered(sessionId)
        }
    }

    /// Whether `sessionId` ended within `endedSessionGrace` and has not had its error yet.
    func isInGrace(_ sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return endingSessions[sessionId] != nil
    }

    /// Deletes what `sessionId` held, unless it had its error, and never holds for it again: a
    /// later event of it is dropped rather than starting a new buffer.
    func discardUntriggered(_ sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        endingSessions.removeValue(forKey: sessionId)?.cancel()
        guard !isTriggeredLocked(sessionId) else { return }
        if !discardedSessionIds.contains(sessionId) {
            discardedSessionIds.append(sessionId)
            if discardedSessionIds.count > Self.discardedSessionsKept {
                discardedSessionIds.removeFirst(discardedSessionIds.count - Self.discardedSessionsKept)
            }
        }
        removeLocked(sessionId)
    }

    /// Deletes every session this instance itself held that has not had its error. A buffer an
    /// earlier launch left for its crash stays: the crash, sent later, is its trigger.
    func discardAllUntriggered() {
        lock.lock()
        defer { lock.unlock() }
        for (id, session) in sessions where !session.metadata.triggered && session.metadata.owner == owner {
            removeLocked(id)
        }
        endingSessions.values.forEach { $0.cancel() }
        endingSessions = [:]
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
    /// memory. nil when nothing is left, in which case the session's files are deleted, or when
    /// the file cannot be read right now, in which case they are kept.
    func nextChunk(of sessionId: String, maxEvents: Int, maxBytes: Int) -> Chunk? {
        // Lines are taken under the lock and decoded after it, so `hold` on the export path does
        // not wait on JSON parsing.
        guard let raw = nextLines(of: sessionId, maxEvents: maxEvents, maxBytes: maxBytes) else { return nil }
        return Chunk(sessionId: sessionId, events: raw.lines.compactMap(Self.decode),
                     fileEndOffset: raw.fileEndOffset, memoryCount: raw.memoryCount)
    }

    private func nextLines(of sessionId: String, maxEvents: Int, maxBytes: Int)
        -> (lines: [Data], fileEndOffset: UInt64?, memoryCount: Int)? {
        lock.lock()
        defer { lock.unlock() }
        guard let session = sessions[sessionId] else { return nil }
        let file: (lines: [Data], endOffset: UInt64)?
        do {
            file = try fileLinesLocked(session, maxEvents: maxEvents, maxBytes: maxBytes)
        } catch {
            Log.e("[ErrorOnlyBuffer] the held events of session \(sessionId) could not be read (\(error)) — kept for a later attempt")
            return nil
        }
        if let file {
            return (file.lines, file.endOffset, 0)
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
        return (Array(session.memory.prefix(taken)), nil, taken)
    }

    /// A missing or short file is a normal case (the OS may purge the folder): what is there goes.
    /// A file that is there but cannot be read now throws: it is not taken for a deleted one.
    private func fileLinesLocked(_ session: Session, maxEvents: Int, maxBytes: Int) throws -> (lines: [Data], endOffset: UInt64)? {
        let fileURL = eventsURL(of: session.metadata.sessionId)
        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            throw error
        }
        guard let start = Int(exactly: session.metadata.sentOffset), start < data.count else { return nil }
        let window = data[start..<min(data.count, start + maxBytes + 1)]
        var lines: [Data] = []
        var consumed = 0
        var lineStart = window.startIndex
        while lines.count < maxEvents, let newline = window[lineStart...].firstIndex(of: 0x0A) {
            let line = window[lineStart..<newline]
            guard consumed + line.count <= maxBytes || consumed == 0 else { break }
            consumed += line.count + 1
            lines.append(Data(line))
            lineStart = window.index(after: newline)
        }
        guard consumed > 0 else { return nil }
        return (lines, session.metadata.sentOffset + UInt64(consumed))
    }

    /// The chunk was delivered or refused for good: it is never sent again. A file fully sent
    /// whose cursor could not be saved is deleted now: left for the drain's next request, an
    /// offline spell, a suspension or a kill before it would leave a restart the older cursor,
    /// sending the last chunk again.
    func commit(_ chunk: Chunk) {
        lock.lock()
        defer { lock.unlock() }
        guard var session = sessions[chunk.sessionId] else { return }
        if let end = chunk.fileEndOffset {
            session.metadata.sentOffset = end
            persistMetadataLocked(&session)
            if session.metadataUnsaved && isFileSentLocked(session) {
                guard !session.memory.isEmpty else {
                    removeLocked(chunk.sessionId)
                    return
                }
                deleteFilesLocked(chunk.sessionId)
            }
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
        persistMetadataLocked(&session)
        sessions[sessionId] = session
    }

    func remove(_ sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        removeLocked(sessionId)
    }

    // MARK: - Earlier launches

    /// Adopts what earlier launches (or SDK instances) left: `keep` decides, from its metadata,
    /// whether a leftover is kept; the rest is deleted, and so is an expired one, whatever `keep`
    /// says — a buffer waiting on a crash that is never sent would otherwise stay forever. Returns
    /// the kept ones that already had their error, oldest first, to drain now.
    func adoptLeftovers(keep: (Metadata) -> Bool) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let now = clock.now()
        var adopted: [Metadata] = []
        for url in files where url.lastPathComponent.hasSuffix(Self.metadataSuffix) {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let metadata = try? JSONDecoder().decode(Metadata.self, from: data) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            guard metadata.owner != owner, sessions[metadata.sessionId] == nil else { continue }
            // An offset no file can have is a corrupt buffer.
            guard Int(exactly: metadata.sentOffset) != nil, !metadata.isExpired(at: now), keep(metadata),
                  FileManager.default.fileExists(atPath: eventsURL(of: metadata.sessionId).path) else {
                deleteFilesLocked(metadata.sessionId)
                continue
            }
            sessions[metadata.sessionId] = Session(metadata: metadata, saved: metadata)
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
        try writer.replace(metadataURL(of: metadata.sessionId), with: JSONEncoder().encode(metadata))
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
