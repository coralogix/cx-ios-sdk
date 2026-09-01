//
//  NavigationInstrumentation.swift
//
//
//  Created by Coralogix Dev Team on 18/06/2024.
//

import Foundation
import CoralogixInternal

extension CoralogixRum {
    public func initializeNavigationInstrumentation() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleNotification(notification:)),
                                               name: .cxRumNotification, object: nil)
    }
    
    @objc func handleNotification(notification: Notification) {
        guard let cxView = notification.object as? CXView else { return }
        self.trackNavigation(for: cxView)
    }
    
    internal func trackNavigation(for cxView: CXView) {
        if cxView.state == .notifyOnAppear,
           let viewManager = coralogixExporter?.getViewManager() {
            if viewManager.isUniqueView(name: cxView.name) {
                // Flush vitals first (freezes ORIGIN, synchronously), then advance so the
                // navigation span freezes the DESTINATION.
                if options?.shouldInitInstrumentation(instrumentation: .mobileVitals) == true {
                    metricsManager.flushAll()
                }

                coralogixExporter?.set(cxView: cxView)

                let span = makeSpan(event: .navigation, source: .console, severity: .info)
                handleAppearStateIfNeeded(cxView: cxView, span: span) { span.end() }
                return
            }
        }
        coralogixExporter?.set(cxView: cxView)
    }
    
    /// Attaches a session-replay frame to an appear-navigation span. `finish` runs exactly once —
    /// including for a disappear event, which captures nothing — and is where the caller ends the
    /// span; the capture resolves asynchronously.
    internal func handleAppearStateIfNeeded(cxView: CXView, span: any Span,
                                           then finish: @escaping () -> Void) {
        guard cxView.state == .notifyOnAppear else {
            finish()
            return
        }
        recordScreenshotForSpan(on: span) { _ in finish() }
    }
}
