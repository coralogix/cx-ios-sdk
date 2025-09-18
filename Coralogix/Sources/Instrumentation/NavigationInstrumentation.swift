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
        
        self.metricsManager.sendMobileVitals()
        
        let span = makeSpan(event: .navigation, source: .console, severity: .info)
        handleAppearStateIfNeeded(cxView: cxView, span: span)
        span.end()
        self.coralogixExporter?.set(cxView: cxView)
    }
    
    internal func handleAppearStateIfNeeded(cxView: CXView, span: any Span) {
        guard cxView.state == .notifyOnAppear else { return }
        
        guard let sessionReplay = SdkManager.shared.getSessionReplay(),
              let coralogixExporter = self.coralogixExporter else {
            Log.e("[SessionReplay] is not initialized")
            return
        }
        
        let screenshotLocation = coralogixExporter.getScreenshotManager().nextScreenshotLocation
        span.setAttribute(key: Keys.screenshotId.rawValue, value: screenshotLocation.screenshotId)
        span.setAttribute(key: Keys.page.rawValue, value: screenshotLocation.page)
        _ = sessionReplay.captureEvent(properties: screenshotLocation.toProperties())
    }
}
