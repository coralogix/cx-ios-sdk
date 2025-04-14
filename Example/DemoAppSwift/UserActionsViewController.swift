//
//  UserActionsViewController.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 20/08/2024.
//

import UIKit

class UserActionsViewController: UITableViewController {
    let items = [Keys.modalPresentation.rawValue,
                 Keys.segmentedCollectionView.rawValue,
                 Keys.pageController.rawValue]
    
    var customView = CustomView(frame: .zero)
    private let customViewHeight: CGFloat = 150
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "user_actions_cell")
        tableView.dataSource = self
        tableView.delegate = self
        self.title = "User Actions Instrumentation"
        
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "user_actions_cell", for: indexPath)
        cell.textLabel?.text = items[indexPath.row]
        return cell
    }
    
    // MARK: - Table view delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        self.customView.updateText("Selected item: \(item)")
        
        if item == Keys.modalPresentation.rawValue {
            let modalViewController = ModalViewController()
            modalViewController.modalPresentationStyle = .fullScreen
            present(modalViewController, animated: true, completion: nil)
        }  else if item == Keys.segmentedCollectionView.rawValue {
            let segmentedCollectionViewController = SegmentedCollectionViewController()
            self.navigationController?.pushViewController(segmentedCollectionViewController, animated: true)
        } else if item == Keys.pageController.rawValue {
            let pageController = PageController()
            self.navigationController?.pushViewController(pageController, animated: true)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
