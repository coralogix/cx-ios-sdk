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
                                               selector: #selector(appDidEnterBackgroundNotification),
                                               name: UIApplication.didEnterBackgroundNotification,
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
        let span = self.getLifeCycleSpan()
        span.setAttribute(key: Keys.type.rawValue,
                          value: Keys.appDidFinishLaunching.rawValue)
        span.end()
    }
    
    @objc private func appDidBecomeActiveNotification(notification: Notification) {
        let span = self.getLifeCycleSpan()
        span.setAttribute(key: Keys.type.rawValue,
                          value: Keys.appDidBecomeActiveNotification.rawValue)
        span.end()
    }
    
    @objc private func appDidEnterBackgroundNotification(notification: Notification) {
        let span = self.getLifeCycleSpan()
        span.setAttribute(key: Keys.type.rawValue,
                          value: Keys.appDidEnterBackgroundNotification.rawValue)
        span.end()
    }
    
    @objc private func appWillTerminateNotification(notification: Notification) {
        let span = self.getLifeCycleSpan()
        span.setAttribute(key: Keys.type.rawValue,
                          value: Keys.appWillTerminateNotification.rawValue)
        span.end()
    }
    
    @objc private func appDidReceiveMemoryWarningNotification(notification: Notification) {
        let span = self.getLifeCycleSpan()
        span.setAttribute(key: Keys.type.rawValue,
                          value: Keys.appDidReceiveMemoryWarningNotification.rawValue)
        span.end()
    }
    
    private func getLifeCycleSpan() -> any Span {
        var span = tracer().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        self.addUserMetadata(to: &span)
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.lifeCycle.rawValue)
        span.setAttribute(key: Keys.source.rawValue, value: Keys.console.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.info.rawValue))
        return span
    }
}
