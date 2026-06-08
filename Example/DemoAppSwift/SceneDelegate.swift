//
//  SceneDelegate.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 19/05/2024.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // BUGV2-6045 leak-harness mode: when launched with `--leak-harness`,
        // swap the storyboard root for LeakHarnessViewController. Triggered
        // by the XCUITest in DemoAppUITests/SessionReplayLeakUITests; never
        // reachable from a normal demo-app launch (no UI affordance).
        //
        // The storyboard auto-loads Main.storyboard into self.window before
        // this method runs (per UISceneStoryboardFile in Info.plist), so
        // swap the existing window's root VC rather than creating a fresh
        // UIWindow — iOS keeps using the storyboard-managed window even if
        // we assign self.window to a new instance.
        if ProcessInfo.processInfo.arguments.contains("--leak-harness") {
            if self.window == nil {
                self.window = UIWindow(windowScene: windowScene)
            }
            self.window?.rootViewController = LeakHarnessViewController()
            self.window?.makeKeyAndVisible()
        } else if ProcessInfo.processInfo.arguments.contains("--leak-harness-navigate") {
            // BUGV2-6045 navigation-transition leak scenario: two screens with
            // sentinel labels pushed/popped rapidly by SessionReplayLeakUITests.
            // Frames captured mid-animation should have both screens' sentinels
            // masked. Any unmasked magenta pixel is a mask-position skew leak.
            if self.window == nil {
                self.window = UIWindow(windowScene: windowScene)
            }
            self.window?.rootViewController = UINavigationController(
                rootViewController: NavigationLeakScreenA()
            )
            self.window?.makeKeyAndVisible()
        } else {
            // Wrap the storyboard-provided navigation root in a UITabBarController so
            // the UITabBar is present for testing cancelled-touch click mark recording.
            if let existingRoot = self.window?.rootViewController {
                let tabBar = UITabBarController()
                existingRoot.tabBarItem = UITabBarItem(
                    title: "Demo",
                    image: UIImage(systemName: "list.bullet"),
                    tag: 0
                )
                let placeholder = UINavigationController(rootViewController: TabPlaceholderViewController())
                placeholder.tabBarItem = UITabBarItem(
                    title: "More",
                    image: UIImage(systemName: "ellipsis.circle"),
                    tag: 1
                )
                tabBar.viewControllers = [existingRoot, placeholder]
                self.window?.rootViewController = tabBar
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }
}

private final class TabPlaceholderViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = "More"
        let label = UILabel()
        label.text = "Tap the tab bar below to test click marks"
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }
}

