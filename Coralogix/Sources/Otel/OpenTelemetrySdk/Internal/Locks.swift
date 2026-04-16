/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Metrics API open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Metrics API project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Metrics API project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#else
import Glibc
#endif
import CoralogixInternal

/// A threading lock based on `libpthread` instead of `libdispatch`.
///
/// This object provides a lock on top of a single `pthread_mutex_t`. This kind
/// of lock is safe to use with `libpthread`-based threading models, such as the
/// one used by NIO.
internal final class Lock {
    fileprivate let mutex: UnsafeMutablePointer<pthread_mutex_t> = UnsafeMutablePointer.allocate(capacity: 1)
    @usableFromInline internal private(set) var initialized = false

    /// Create a new lock.
    public init() {
        let err = pthread_mutex_init(self.mutex, nil)
        if err != 0 {
            Log.e("[Coralogix] pthread_mutex_init failed with error \(err)")
        } else {
            initialized = true
        }
    }

    deinit {
        guard initialized else {
            self.mutex.deallocate()
            return
        }
        let err = pthread_mutex_destroy(self.mutex)
        if err != 0 { Log.e("[Coralogix] pthread_mutex_destroy failed with error \(err)") }
        initialized = false
        self.mutex.deallocate()
    }

    /// Acquire the lock.
    ///
    /// Whenever possible, consider using `withLock` instead of this method and
    /// `unlock`, to simplify lock handling.
    @discardableResult
    public func lock() -> Bool {
        guard initialized else {
            Log.e("[Coralogix] Attempted to lock uninitialized mutex")
            return false
        }
        let err = pthread_mutex_lock(self.mutex)
        if err != 0 {
            Log.e("[Coralogix] pthread_mutex_lock failed with error \(err)")
            return false
        }
        return true
    }

    /// Release the lock.
    ///
    /// Whenever possible, consider using `withLock` instead of this method and
    /// `lock`, to simplify lock handling.
    public func unlock() {
        guard initialized else {
            Log.w("[Coralogix] Attempted to unlock uninitialized mutex")
            return
        }
        let err = pthread_mutex_unlock(self.mutex)
        if err != 0 { Log.w("[Coralogix] pthread_mutex_unlock failed with error \(err)") }
    }
}

extension Lock {
    /// Acquire the lock for the duration of the given block.
    ///
    /// If the lock cannot be acquired (uninitialized mutex or `pthread_mutex_lock` failure), `body` is **not** executed
    /// and `defaultOnLockFailure` is returned instead. This avoids both data races and silent drops without a defined value.
    ///
    /// - Parameters:
    ///   - defaultOnLockFailure: Value to return when the lock cannot be acquired.
    ///   - body: The block to execute while holding the lock.
    @inlinable
    internal func withLock<T>(
        defaultOnLockFailure: @autoclosure () -> T,
        _ body: () throws -> T
    ) rethrows -> T {
        let locked = self.lock()
        defer {
            if locked { self.unlock() }
        }
        guard locked else {
            Log.e("[Coralogix] Lock acquisition failed — returning default; critical section not run")
            return defaultOnLockFailure()
        }
        return try body()
    }

    // specialise Void return (for performance)
    @inlinable
    internal func withLockVoid(_ body: () throws -> Void) rethrows {
        guard initialized else {
            Log.e("[Coralogix] Lock not initialized — skipping critical section")
            return
        }
        let locked = self.lock()
        guard locked else { return }
        defer { self.unlock() }
        try body()
    }
}

/// A reader-writer threading lock based on `libpthread` instead of `libdispatch`.
///
/// This object provides a lock on top of a single `pthread_rwlock_t`. This kind
/// of lock is safe to use with `libpthread`-based threading models, such as the
/// one used by NIO.
internal final class ReadWriteLock {
    fileprivate let rwlock: UnsafeMutablePointer<pthread_rwlock_t> = UnsafeMutablePointer.allocate(capacity: 1)
    @usableFromInline internal private(set) var initialized = false

    /// Create a new lock.
    public init() {
        let err = pthread_rwlock_init(self.rwlock, nil)
        if err != 0 {
            Log.e("[Coralogix] pthread_rwlock_init failed with error \(err)")
        } else {
            initialized = true
        }
    }

    deinit {
        guard initialized else {
            self.rwlock.deallocate()
            return
        }
        let err = pthread_rwlock_destroy(self.rwlock)
        if err != 0 { Log.e("[Coralogix] pthread_rwlock_destroy failed with error \(err)") }
        initialized = false
        self.rwlock.deallocate()
    }

    /// Acquire a reader lock.
    ///
    /// Whenever possible, consider using `withReaderLock` instead of this method and
    /// `unlock`, to simplify lock handling.
    @discardableResult
    public func lockRead() -> Bool {
        guard initialized else {
            Log.e("[Coralogix] Attempted to read-lock uninitialized rwlock")
            return false
        }
        let err = pthread_rwlock_rdlock(self.rwlock)
        if err != 0 {
            Log.e("[Coralogix] pthread_rwlock_rdlock failed with error \(err)")
            return false
        }
        return true
    }

    /// Acquire a writer lock.
    ///
    /// Whenever possible, consider using `withWriterLock` instead of this method and
    /// `unlock`, to simplify lock handling.
    @discardableResult
    public func lockWrite() -> Bool {
        guard initialized else {
            Log.e("[Coralogix] Attempted to write-lock uninitialized rwlock")
            return false
        }
        let err = pthread_rwlock_wrlock(self.rwlock)
        if err != 0 {
            Log.e("[Coralogix] pthread_rwlock_wrlock failed with error \(err)")
            return false
        }
        return true
    }

    /// Release the lock.
    ///
    /// Whenever possible, consider using `withReaderLock`/`withWriterLock` instead
    /// of this method and `lockRead`/`lockWrite`, to simplify lock handling.
    public func unlock() {
        guard initialized else {
            Log.w("[Coralogix] Attempted to unlock uninitialized rwlock")
            return
        }
        let err = pthread_rwlock_unlock(self.rwlock)
        if err != 0 { Log.w("[Coralogix] pthread_rwlock_unlock failed with error \(err)") }
    }
}

extension ReadWriteLock {
    /// If the reader lock cannot be acquired, `body` is not executed and `defaultOnLockFailure` is returned.
    @inlinable
    internal func withReaderLock<T>(
        defaultOnLockFailure: @autoclosure () -> T,
        _ body: () throws -> T
    ) rethrows -> T {
        let locked = self.lockRead()
        defer {
            if locked { self.unlock() }
        }
        guard locked else {
            Log.e("[Coralogix] ReadWriteLock read lock acquisition failed — returning default; critical section not run")
            return defaultOnLockFailure()
        }
        return try body()
    }

    /// If the writer lock cannot be acquired, `body` is not executed and `defaultOnLockFailure` is returned.
    @inlinable
    internal func withWriterLock<T>(
        defaultOnLockFailure: @autoclosure () -> T,
        _ body: () throws -> T
    ) rethrows -> T {
        let locked = self.lockWrite()
        defer {
            if locked { self.unlock() }
        }
        guard locked else {
            Log.e("[Coralogix] ReadWriteLock write lock acquisition failed — returning default; critical section not run")
            return defaultOnLockFailure()
        }
        return try body()
    }

    // specialise Void return — skips body entirely if lock fails
    @inlinable
    internal func withReaderLockVoid(_ body: () throws -> Void) rethrows {
        guard initialized else {
            Log.e("[Coralogix] ReadWriteLock not initialized — skipping critical section")
            return
        }
        let locked = self.lockRead()
        guard locked else { return }
        defer { self.unlock() }
        try body()
    }

    // specialise Void return — skips body entirely if lock fails
    @inlinable
    internal func withWriterLockVoid(_ body: () throws -> Void) rethrows {
        guard initialized else {
            Log.e("[Coralogix] ReadWriteLock not initialized — skipping critical section")
            return
        }
        let locked = self.lockWrite()
        guard locked else { return }
        defer { self.unlock() }
        try body()
    }
}
