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
        
        let span = self.getNavigationSpan()
        
        handleAppearStateIfNeeded(cxView: cxView, span: span)
        handleUniqueViewIfNeeded(cxView: cxView, span: span)
        
        span.end()
        self.coralogixExporter?.set(cxView: cxView)
    }
    
    internal func handleAppearStateIfNeeded(cxView: CXView, span: any Span) {
        guard cxView.state == .notifyOnAppear else { return }
        
        guard let sessionReplay = SdkManager.shared.getSessionReplay() else {
            Log.e("[SessionReplay] is not initialized")
            return
        }
        
        let screenshotLocation = self.screenshotManager.nextScreenshotLocation
        span.setAttribute(key: Keys.screenshotId.rawValue, value: screenshotLocation.screenshotId)
        span.setAttribute(key: Keys.page.rawValue, value: screenshotLocation.page)
        sessionReplay.captureEvent(properties: screenshotLocation.toProperties())
    }
    
    internal func handleUniqueViewIfNeeded(cxView: CXView, span: any Span) {
        guard viewManager.isUniqueView(name: cxView.name),
              let sessionManager = sessionManager else { return }
        let timestamp: TimeInterval = Date().timeIntervalSince1970
        let snapshot = SnapshotConext(
            timestemp: timestamp,
            errorCount: sessionManager.getErrorCount(),
            viewCount: viewManager.getUniqueViewCount() + 1,
            clickCount: sessionManager.getClickCount(),
            hasRecording: sessionManager.hasRecording
        )
        
        let dict = Helper.convertDictionary(snapshot.getDictionary())
        let jsonString = Helper.convertDictionayToJsonString(dict: dict)
        
        span.setAttribute(key: Keys.snapshotContext.rawValue, value: jsonString)
    }
    
    internal func getNavigationSpan() -> any Span {
        var span = tracerProvider().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        self.addUserMetadata(to: &span)
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.navigation.rawValue)
        span.setAttribute(key: Keys.source.rawValue, value: Keys.console.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.info.rawValue))
        return span
    }
}
