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
        if let cxView = notification.object as? CXView {
            let timestemp: TimeInterval = Date().timeIntervalSince1970
            if cxView.state == .notifyOnAppear {
                if let sessionReplay = SdkManager.shared.getSessionReplay() {
                    sessionReplay.captureEvent(properties: [Keys.timestamp.rawValue: timestemp])
                } else {
                    Log.e("[SessionReplay] is not initialized")
                }
            }

            if viewManager.isUniqueView(name: cxView.name),
               let sessionManager = self.sessionManager {
                let span = self.getNavigationSpan()

                let snapshot = SnapshotConext(timestemp: timestemp,
                                              errorCount: sessionManager.getErrorCount(),
                                              viewCount: self.viewManager.getUniqueViewCount() + 1,
                                              clickCount: sessionManager.getClickCount(),
                                              hasRecording: sessionManager.hasRecording)
                let dict = Helper.convertDictionary(snapshot.getDictionary())
                span.setAttribute(key: Keys.snapshotContext.rawValue,
                                  value: Helper.convertDictionayToJsonString(dict: dict))
                self.coralogixExporter?.set(cxView: cxView)
                span.end()
            } else {
                self.coralogixExporter?.set(cxView: cxView)
            }
        }
    }
    
    private func getNavigationSpan() -> any Span {
        var span = tracer().spanBuilder(spanName: Keys.iosSdk.rawValue).startSpan()
        self.addUserMetadata(to: &span)
        span.setAttribute(key: Keys.eventType.rawValue, value: CoralogixEventType.navigation.rawValue)
        span.setAttribute(key: Keys.source.rawValue, value: Keys.console.rawValue)
        span.setAttribute(key: Keys.severity.rawValue, value: AttributeValue.int(CoralogixLogSeverity.info.rawValue))
        return span
    }
}
