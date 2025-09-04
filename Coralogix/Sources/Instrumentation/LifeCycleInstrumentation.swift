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
        self.makeSpan(type: .type, value: .appDidFinishLaunching)
    }
    
    @objc private func appDidBecomeActiveNotification(notification: Notification) {
        self.makeSpan(type: .type, value: .appDidBecomeActiveNotification)
    }
    
    @objc private func appDidEnterBackgroundNotification(notification: Notification) {
        self.makeSpan(type: .type, value: .appDidEnterBackgroundNotification)
    }
    
    @objc private func appWillTerminateNotification(notification: Notification) {
        self.makeSpan(type: .type, value: .appWillTerminateNotification)
    }
    
    @objc private func appDidReceiveMemoryWarningNotification(notification: Notification) {
        self.makeSpan(type: .type, value: .appDidReceiveMemoryWarningNotification)
    }
    
    private func makeSpan(type: Keys, value: Keys) {
        var span = tracerProvider().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.lifeCycle.rawValue)
        span.setAttribute(key: Keys.source.rawValue, value: Keys.console.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.info.rawValue))
        span.setAttribute(key: type.rawValue, value: value.rawValue)
        self.addUserMetadata(to: &span)
        span.end()
    }
}
