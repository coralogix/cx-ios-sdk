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
        // Hybrid apps report routes as view names, and a route can carry a query. The raw name is
        // kept to decide whether the view changed: two routes that mask alike are still two views.
        let cxView = CXView(state: cxView.state,
                            name: UrlMasker.Masker(options?.urlMasking ?? UrlMaskingOptions()).maskViewName(cxView.name),
                            rawName: cxView.identity)
        if cxView.state == .notifyOnAppear,
           let viewManager = coralogixExporter?.getViewManager() {
            if viewManager.isUniqueView(name: cxView.identity) {
                // Flush vitals first (freezes ORIGIN, synchronously), then advance so the
                // navigation span freezes the DESTINATION.
                if options?.shouldInitInstrumentation(instrumentation: .mobileVitals) == true {
                    metricsManager.flushAll()
                }

                coralogixExporter?.set(cxView: cxView)

                makeSpan(event: .navigation, source: nil, severity: .info).end()
                return
            }
        }
        coralogixExporter?.set(cxView: cxView)
    }

}
