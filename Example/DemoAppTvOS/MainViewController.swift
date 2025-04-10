//
//  MainViewController.swift
//  DemoAppTvOS
//
//  Created by Coralogix Dev Team on 18/08/2024.
//

import UIKit
import Coralogix

class MainViewController: UITableViewController {
    let data = [Keys.failureNetworkRequest.rawValue,
                Keys.succesfullNetworkRequest.rawValue,
                Keys.sendNSException.rawValue,
                Keys.sendNSError.rawValue,
                Keys.sendErrorString.rawValue,
                Keys.sendLogWithData.rawValue,
                Keys.sendCrash.rawValue,
                Keys.shutDownCoralogixRum.rawValue,
                Keys.updateLabels.rawValue,
                Keys.modalPresentation.rawValue,
                Keys.segmentedCollectionView.rawValue]
    
    var coralogixRum: CoralogixRum?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            self.coralogixRum = appDelegate.coralogixRum
        }
        
        // Register a basic UITableViewCell
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        
        // Adjust the table view for tvOS appearance
        tableView.backgroundColor = .clear
        tableView.rowHeight = 80 // Make rows larger for better tvOS appearance
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return data.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        
        // Configure the cell appearance
        cell.textLabel?.text = data[indexPath.row]
        cell.textLabel?.font = UIFont.systemFont(ofSize: 36, weight: .bold)
        cell.textLabel?.textColor = .white
        cell.backgroundColor = .darkGray
        cell.layer.cornerRadius = 10
        cell.clipsToBounds = true
        cell.selectionStyle = .none
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let coralogixRum = self.coralogixRum else {
            return
        }

        let item = data[indexPath.row]

        print("Selected \(data[indexPath.row])")
        if item == Keys.failureNetworkRequest.rawValue {
            NetworkSim.failureNetworkRequest()
        } else if item == Keys.succesfullNetworkRequest.rawValue {
            NetworkSim.sendSuccesfullRequest()
        } else if item == Keys.sendNSException.rawValue {
            ErrorSim.sendNSException(cxRum: coralogixRum)
        } else if item == Keys.sendNSError.rawValue {
            ErrorSim.sendNSError(cxRum: coralogixRum)
        } else if item == Keys.sendErrorString.rawValue {
            ErrorSim.sendStringError(cxRum: coralogixRum)
        } else if item == Keys.sendLogWithData.rawValue {
            ErrorSim.sendLog(cxRum: coralogixRum)
        } else if item == Keys.sendCrash.rawValue {
            CrashSim.simulateRandomCrash()
        } else if item == Keys.shutDownCoralogixRum.rawValue {
            coralogixRum.shutdown()
        } else if item == Keys.sendLogWithData.rawValue {
            ErrorSim.sendLog(cxRum: coralogixRum)
        } else if item ==  Keys.updateLabels.rawValue {
            coralogixRum.setLabels(labels: ["item3" : "playstation 4", "itemPrice" : 400])
        } else if item == Keys.segmentedCollectionView.rawValue {
            let segmentedCollectionViewController = SegmentedCollectionViewController()
            self.navigationController?.pushViewController(segmentedCollectionViewController, animated: true)
        } else if item == Keys.modalPresentation.rawValue {
            let modalViewController = ModalViewController()
            modalViewController.modalPresentationStyle = .fullScreen
            present(modalViewController, animated: true, completion: nil)
        }
    }
    
    // Customize the appearance when the cell is focused
    override func tableView(_ tableView: UITableView, didUpdateFocusIn context: UITableViewFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        if let previousIndexPath = context.previouslyFocusedIndexPath,
           let previousCell = tableView.cellForRow(at: previousIndexPath) {
            previousCell.backgroundColor = .darkGray
            previousCell.textLabel?.textColor = .white
            previousCell.transform = .identity
        }
        
        if let nextIndexPath = context.nextFocusedIndexPath,
           let nextCell = tableView.cellForRow(at: nextIndexPath) {
            nextCell.backgroundColor = .lightGray
            nextCell.textLabel?.textColor = .black
            nextCell.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
        }
    }
}

