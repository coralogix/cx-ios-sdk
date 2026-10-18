//
//  AppDelegate.swift
//  DemoAppTvOS
//
//  Created by Coralogix Dev Team on 18/08/2024.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        CoralogixRumManager.shared.initialize(application: "DemoApp-tvOS")
        if CommandLine.arguments.contains(SmokeRun.launchArgument) {
            SmokeRun.start()
        }
        return true
    }
}

/// Fires every non-destructive menu action without the remote, so CI can check the whole
/// session against the schema-validator (`tool/run_tvos_smoke.sh`). The simulator cannot
/// inject Siri Remote presses, and XCUITest would add a target only to press "select".
enum SmokeRun {
    static let launchArgument = "--cx-smoke"

    static func start() {
        let sessionId = CoralogixRumManager.shared.getSessionId()?.lowercased() ?? "none"
        print("CX_SESSION_ID=\(sessionId)")

        NetworkSim.sendSuccesfullRequest()
        NetworkSim.failureNetworkRequest()
        ErrorSim.sendNSException()
        ErrorSim.sendNSError()
        ErrorSim.sendError()
        ErrorSim.sendMessageDataError()
        ErrorSim.sendErrorLog()
        CoralogixRumManager.shared.sdk.set(labels: ["item3": "playstation 4", "itemPrice": 400])
        // The simulator has no Siri Remote, so the interaction goes through the public API,
        // which builds the same interaction_context a native capture would.
        CoralogixRumManager.shared.sdk.setUserInteraction(["event_name": "click",
                                                           "target_element": "SmokeButton"])
        print("CX_SMOKE_ACTIONS_SENT")
    }
}
