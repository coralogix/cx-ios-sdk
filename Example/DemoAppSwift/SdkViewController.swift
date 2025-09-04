//
//  SdkViewController.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 20/08/2024.
//

import UIKit
import Coralogix

class SdkViewController: UITableViewController {
    let items = [Keys.shutDownCoralogixRum.rawValue,
                 Keys.updateLabels.rawValue,
                 Keys.reportMobileVitalsMeasurement.rawValue]
    
    var customView = CustomView(frame: .zero)
    private let customViewHeight: CGFloat = 150
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "sdk_cell")
        tableView.dataSource = self
        tableView.delegate = self
        self.title = "SDK Instrumentation"
        
        // Create the custom view
        self.customView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add the custom view to the table view's parent view
        view.addSubview(self.customView)
        
        // Set up constraints for the custom view
        NSLayoutConstraint.activate([
            customView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            customView.heightAnchor.constraint(equalToConstant: customViewHeight),
            customView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Adjust the table view's content inset to account for the custom view's height
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: customViewHeight, right: 0)
        tableView.scrollIndicatorInsets = tableView.contentInset
    }
    
    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Dequeue a cell from the table view
        let cell = tableView.dequeueReusableCell(withIdentifier: "sdk_cell", for: indexPath)
        cell.textLabel?.text = items[indexPath.row]
        return cell
    }
    
    // MARK: - Table view delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        self.customView.updateText("Selected item: \(item)")
        
        if item == Keys.shutDownCoralogixRum.rawValue {
            CoralogixRumManager.shared.sdk.shutdown()
        } else if item == Keys.updateLabels.rawValue {
            CoralogixRumManager.shared.sdk.set(labels: ["item3" : "playstation 4", "itemPrice" : 400])
        } else if item == Keys.reportMobileVitalsMeasurement.rawValue {
            CoralogixRumManager.shared.sdk.reportMobileVitalsMeasurement(type: "custom metric", value: 10.0, units: "ms")
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

