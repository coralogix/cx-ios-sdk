//
//  LifeCycleInstrumentation.swift
//
//
//  Created by Coralogix Dev TEAM on 29/09/2024.
//

#if canImport(UIKit)
import UIKit
#endif
import CoralogixInternal

extension CoralogixRum {
    public func initializeLifeCycleInstrumentation() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidFinishLaunching),
                                               name: UIApplication.didFinishLaunchingNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidBecomeActiveNotification),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appWillTerminateNotification),
                                               name: UIApplication.willTerminateNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidReceiveMemoryWarningNotification),
                                               name: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil)
    }
    
    @objc private func appDidFinishLaunching(notification: Notification) {
        self.makeSpan(type: .type, value: .appDidFinishLaunching)
    }
    
    @objc private func appDidBecomeActiveNotification(notification: Notification) {
        self.makeSpan(type: .type, value: .appDidBecomeActiveNotification)
    }
    
    /// Registers the pre-suspension flush. Always active, unlike the life-cycle events above.
    ///
    /// Delivery is not telemetry. Buffered spans have to reach the exporter before the app suspends
    /// whatever the sampling roll decided — otherwise a sampled-out session drops exactly the events
    /// `excludeFromSampling` exists to guarantee, and iOS offers no `lifecycle` category to opt back
    /// into. Emitting the life-cycle *event* stays gated; getting the batch out does not.
    ///
    /// One observer does both, in that order, so the background event is itself included in the
    /// flush it triggers. Two observers on the same notification would fire in an unspecified order
    /// and could leave that span behind.
    internal func initializeBackgroundFlush() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidEnterBackgroundNotification),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
    }

    @objc private func appDidEnterBackgroundNotification(notification: Notification) {
        if self.isInstrumentationInstalled(.lifeCycle) {
            self.makeSpan(type: .type, value: .appDidEnterBackgroundNotification)
        }

        // Request background time to ensure flush/export completes before app suspension.
        // The expiration handler ensures we don't leak background task identifiers.
        var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(expirationHandler: {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        })

        self.flush {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }
    
    @objc private func appWillTerminateNotification(notification: Notification) {
        self.makeSpan(type: .type, value: .appWillTerminateNotification)
    }
    
    @objc private func appDidReceiveMemoryWarningNotification(notification: Notification) {
        self.makeSpan(type: .type, value: .appDidReceiveMemoryWarningNotification)
    }
    
    private func makeSpan(type: Keys, value: Keys) {
        let span = makeSpan(event: .lifeCycle, source: .console, severity: .info)
        span.setAttribute(key: type.rawValue, value: value.rawValue)
        span.end()
    }
}
