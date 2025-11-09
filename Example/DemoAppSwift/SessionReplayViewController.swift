//
//  SessionReplayViewController.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 03/11/2024.
//

import UIKit
import Coralogix

class SessionReplayViewController: UITableViewController {
    let items = [Keys.startRecoding.rawValue,
                 Keys.stopRecoding.rawValue,
                 Keys.captureEvent.rawValue,
                 Keys.isRecording.rawValue,
                 Keys.isInitialized.rawValue,
                 Keys.updateSessionId.rawValue,
                 Keys.creditCardElement.rawValue,
                 Keys.creditCardImgElement.rawValue,
                 Keys.creditCardImgElement.rawValue,
                 Keys.creditCardImgElement.rawValue,
                 Keys.creditCardImgElement.rawValue,
                 Keys.creditCardImgElement.rawValue]
    
    let images = ["master.png", "testImg2.png", "american.png", "visa.png", "testImg.png"]
    var customView = CustomView(frame: .zero)
    private let customViewHeight: CGFloat = 150

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "session_replay_cell")
        tableView.register(CreditCardInputCell.self, forCellReuseIdentifier: "CreditCardInputCell")
        tableView.register(FullImageCell.self, forCellReuseIdentifier: "full_image_cell")
        tableView.dataSource = self
        tableView.delegate = self
        self.title = "Session Replay"
        
//        // Create the custom view
//        self.customView.translatesAutoresizingMaskIntoConstraints = false
//        
//        // Add the custom view to the table view's parent view
//        view.addSubview(self.customView)
//        
//        // Set up constraints for the custom view
//        NSLayoutConstraint.activate([
//            customView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//            customView.heightAnchor.constraint(equalToConstant: customViewHeight),
//            customView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
//        ])
//
// //        Adjust the table view's content inset to account for the custom view's height
//        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: customViewHeight, right: 0)
//        tableView.scrollIndicatorInsets = tableView.contentInset
    }
    
    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellText = items[indexPath.row]
        
        if cellText == Keys.creditCardElement.rawValue {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "CreditCardInputCell", for: indexPath) as? CreditCardInputCell else {
                return UITableViewCell()
            }
            return cell
        } else if  cellText == Keys.creditCardImgElement.rawValue {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "full_image_cell", for: indexPath) as? FullImageCell else {
                return UITableViewCell()
            }
            cell.backgroundColor = .white
            if let randomImage = images.randomElement() {
                cell.configure(with: randomImage)                
            }
            return cell
        } else {
            // Dequeue a cell from the table view
            let cell = tableView.dequeueReusableCell(withIdentifier: "session_replay_cell", for: indexPath)
            cell.textLabel?.text = cellText
            return cell
        }
    }
    
    // MARK: - Table view delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        self.customView.updateText("Selected item: \(item)")
        
        if item == Keys.startRecoding.rawValue {
            CoralogixRumManager.shared.sdk.startRecording()
        } else if item == Keys.stopRecoding.rawValue {
            CoralogixRumManager.shared.sdk.stopRecording()
        } else if item == Keys.captureEvent.rawValue {
            CoralogixRumManager.shared.sdk.captureEvent()
        } else if item == Keys.updateSessionId.rawValue {
            CoralogixRumManager.shared.sdk.update(sessionId: UUID().uuidString.lowercased())
        } else if item == Keys.isRecording.rawValue {
            self.showAlertView(message: "isRecording: \(CoralogixRumManager.shared.sdk.isSRRecording())")
        } else if item == Keys.isInitialized.rawValue {
            self.showAlertView(message: "isInitialized: \(CoralogixRumManager.shared.sdk.isSRInitialized())")
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let cellText = items[indexPath.row]
        if cellText == Keys.creditCardImgElement.rawValue {
            return 150
        }
        return UITableView.automaticDimension
    }
    
    public func showAlertView(message: String) {
        let alert = UIAlertController(title: "Alert", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        self.present(alert, animated: true)
    }
}
