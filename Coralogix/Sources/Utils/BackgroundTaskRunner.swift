//
//  BackgroundTaskRunner.swift
//  Coralogix
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Background time held for one piece of work. Ends at most once, whichever of its owner and the
/// system's expiration gets there first.
final class BackgroundTask {
    private let lock = NSLock()
    private var endAction: (() -> Void)?

    init(end: @escaping () -> Void) {
        self.endAction = end
    }

    func end() {
        lock.lock()
        let action = endAction
        endAction = nil
        lock.unlock()
        action?()
    }
}

protocol BackgroundTaskRunning: AnyObject {
    /// Asks for time to finish `name` should the app move to the background. If the system takes
    /// that time back first, `expiration` runs and the task is ended right after it.
    func begin(name: String, expiration: @escaping () -> Void) -> BackgroundTask
}

final class ApplicationBackgroundTaskRunner: BackgroundTaskRunning {
    func begin(name: String, expiration: @escaping () -> Void) -> BackgroundTask {
        let lock = NSLock()
        var identifier = UIBackgroundTaskIdentifier.invalid
        var ended = false
        let task = BackgroundTask {
            lock.lock()
            ended = true
            let running = identifier
            identifier = .invalid
            lock.unlock()
            if running != .invalid {
                UIApplication.shared.endBackgroundTask(running)
            }
        }

        let begun = UIApplication.shared.beginBackgroundTask(withName: name) {
            expiration()
            task.end()
        }

        // The owner may end the task before `beginBackgroundTask` has returned its identifier.
        lock.lock()
        let endedAlready = ended
        if !endedAlready { identifier = begun }
        lock.unlock()
        if endedAlready, begun != .invalid {
            UIApplication.shared.endBackgroundTask(begun)
        }
        return task
    }
}
