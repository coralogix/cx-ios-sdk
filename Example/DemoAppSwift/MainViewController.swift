//
//  MainViewController.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 19/05/2024.
//

import UIKit
import Coralogix
import MetricKit

class MainViewController: UITableViewController {
    let items = [Keys.networkInstumentation.rawValue,
                 Keys.errorInstumentation.rawValue,
                 Keys.sdkFunctions.rawValue,
                 Keys.userActionsInstumentation.rawValue,
                 Keys.sessionReplay.rawValue,
                 Keys.clock.rawValue]
   
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        self.title = CoralogixRumManager.shared.getSessionId() ?? "No Session"
        // then tell the nav bar to use a 10‑point font
        navigationController?.navigationBar.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 10)
        ]
        
        // 3) Add a Copy button on the right
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Copy",
            style: .plain,
            target: self,
            action: #selector(copySessionIDToClipboard)
        )
    }
    
    @objc private func copySessionIDToClipboard() {
        guard let sessionID = CoralogixRumManager.shared.getSessionId() else {
            let alert = UIAlertController(title: nil,
                                          message: "No session ID available",
                                          preferredStyle: .alert)
            present(alert, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                alert.dismiss(animated: true)
            }
            return
        }
        
        UIPasteboard.general.string = sessionID
        
        // (Optional) quick user feedback
        let alert = UIAlertController(title: nil,
                                      message: "Copied to clipboard!",
                                      preferredStyle: .alert)
        present(alert, animated: true)
        
        // auto‑dismiss after 1s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            alert.dismiss(animated: true, completion: nil)
        }
    }

    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = items[indexPath.row]
        return cell
    }
    
    // MARK: - Table view delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Handle row selection
        let item = items[indexPath.row]
        
        print("Selected item: \(item)")
        
        if item == Keys.networkInstumentation.rawValue {
            let networkViewController = NetworkViewController()
            self.navigationController?.pushViewController(networkViewController, animated: true)
        } else if item == Keys.errorInstumentation.rawValue {
            let errorViewController = ErrorViewController()
            self.navigationController?.pushViewController(errorViewController, animated: true)
        } else if item == Keys.sdkFunctions.rawValue {
            let sdkViewController = SdkViewController()
            self.navigationController?.pushViewController(sdkViewController, animated: true)
        } else if item == Keys.userActionsInstumentation.rawValue {
            let userActionsViewController = UserActionsViewController()
            self.navigationController?.pushViewController(userActionsViewController, animated: true)
        } else if item == Keys.sessionReplay.rawValue {
            let sessionReplayViewController = SessionReplayViewController()
            self.navigationController?.pushViewController(sessionReplayViewController, animated: true)
        } else if item == Keys.clock.rawValue {
            let clockViewController = ClockViewController()
            self.navigationController?.pushViewController(clockViewController, animated: true)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

