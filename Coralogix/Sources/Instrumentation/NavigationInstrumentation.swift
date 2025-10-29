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
                metricsManager.sendMobileVitals()
                
                var span = makeSpan(event: .navigation, source: .console, severity: .info)
                handleAppearStateIfNeeded(cxView: cxView, span: &span)
                span.end()
            }
            coralogixExporter?.set(cxView: cxView)
        }
    }
    
    internal func handleAppearStateIfNeeded(cxView: CXView, span: inout any Span) {
        guard cxView.state == .notifyOnAppear else { return }
        
        guard let sessionReplay = SdkManager.shared.getSessionReplay(),
              let coralogixExporter = self.coralogixExporter else {
            Log.e("[SessionReplay] is not initialized")
            return
        }
        
        let screenshotLocation = coralogixExporter.getScreenshotManager().nextScreenshotLocation
        let result = sessionReplay.captureEvent(properties: screenshotLocation.toProperties())
        switch result {
        case .success:
            self.applyScreenshotAttributes(screenshotLocation, to: &span)
        case .failure(let error):
            if error == .skippingEvent {
                self.coralogixExporter?.getScreenshotManager().revertScreenshotCounter()
            }
        }
    }
}
