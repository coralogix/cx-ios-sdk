//
//  NetworkViewController.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 20/08/2024.
//

import UIKit
import Coralogix

class NetworkViewController: UITableViewController {
    let items = [Keys.failureNetworkRequest.rawValue,
                 Keys.succesfullNetworkRequest.rawValue,
                 Keys.failureNetworkRequestFlutter.rawValue,
                 Keys.succesfullNetworkRequestFlutter.rawValue,
                 Keys.succesfullAlamofire.rawValue,
                 Keys.failureAlamofire.rawValue,
                 Keys.alamofireUploadRequest.rawValue,
                 Keys.afnetworkingRequest.rawValue,
                 Keys.postRequestToServer.rawValue,
                 Keys.getRequestToServer.rawValue]
    
    var customView = CustomView(frame: .zero)
    private let customViewHeight: CGFloat = 150
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "network_cell")
        tableView.dataSource = self
        tableView.delegate = self
        self.title = "Network Instrumentation"
        
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "network_cell", for: indexPath)
        cell.textLabel?.text = items[indexPath.row]
        return cell
    }
    
    // MARK: - Table view delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        self.customView.updateText("Selected item: \(item)")
        
        if item == Keys.failureNetworkRequest.rawValue {
            NetworkSim.failureNetworkRequest()
        } else if item == Keys.succesfullNetworkRequest.rawValue {
            NetworkSim.sendSuccesfullRequest()
        } else if item == Keys.succesfullNetworkRequestFlutter.rawValue {
            NetworkSim.setNetworkRequestContextSuccsess()
        } else if item == Keys.failureNetworkRequestFlutter.rawValue {
            NetworkSim.setNetworkRequestContextFailure()
        } else if item ==  Keys.succesfullAlamofire.rawValue {
            NetworkSim.succesfullAlamofire()
        } else if item == Keys.failureAlamofire.rawValue {
            NetworkSim.failureAlamofire()
        } else if item == Keys.alamofireUploadRequest.rawValue {
            let fileUrl = NetworkSim.createSampleFile(sizeInMB: 10)
            NetworkSim.uploadFile(fileURL: fileUrl)
        } else if item == Keys.afnetworkingRequest.rawValue {
            NetworkSim.semdAFNetworkingRequest()
        } else if item == Keys.postRequestToServer.rawValue {
            NetworkSim.performPostRequest()
        } else if item == Keys.getRequestToServer.rawValue {
            NetworkSim.performGetRequest()
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

