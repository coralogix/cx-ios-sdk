//
//  MainViewController.swift
//  DemoAppTvOS
//
//  Created by Coralogix Dev Team on 18/08/2024.
//

import UIKit

class MainViewController: UITableViewController {
    private let items: [Keys] = [.failureNetworkRequest,
                                 .succesfullNetworkRequest,
                                 .sendNSException,
                                 .sendNSError,
                                 .sendError,
                                 .sendMessageDataError,
                                 .sendLogError,
                                 .updateLabels,
                                 .modalPresentation,
                                 .segmentedCollectionView,
                                 .sendCrash,
                                 .shutDownCoralogixRum]

    private let sessionIdLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = .clear
        tableView.rowHeight = 80
        tableView.tableHeaderView = makeSessionHeader()
    }

    // The session rotates (idle timeout, shutdown), so re-read it whenever the menu returns.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionIdLabel.text = CoralogixRumManager.shared.getSessionId()?.lowercased() ?? "No session"
    }

    // tvOS has no pasteboard, so unlike the iOS demos this only displays the id.
    private func makeSessionHeader() -> UIView {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 150))

        let titleLabel = UILabel()
        titleLabel.text = "Session ID"
        titleLabel.font = UIFont.systemFont(ofSize: 28, weight: .semibold)
        titleLabel.textColor = .lightGray

        sessionIdLabel.font = UIFont.monospacedSystemFont(ofSize: 40, weight: .medium)
        sessionIdLabel.textColor = .white
        sessionIdLabel.adjustsFontSizeToFitWidth = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, sessionIdLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])
        return header
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = items[indexPath.row].rawValue
        cell.textLabel?.font = UIFont.systemFont(ofSize: 36, weight: .bold)
        cell.textLabel?.textColor = .white
        cell.backgroundColor = .darkGray
        cell.layer.cornerRadius = 10
        cell.clipsToBounds = true
        cell.selectionStyle = .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        print("Selected \(item.rawValue)")

        switch item {
        case .failureNetworkRequest:
            NetworkSim.failureNetworkRequest()
        case .succesfullNetworkRequest:
            NetworkSim.sendSuccesfullRequest()
        case .sendNSException:
            ErrorSim.sendNSException()
        case .sendNSError:
            ErrorSim.sendNSError()
        case .sendError:
            ErrorSim.sendError()
        case .sendMessageDataError:
            ErrorSim.sendMessageDataError()
        case .sendLogError:
            ErrorSim.sendErrorLog()
        case .updateLabels:
            CoralogixRumManager.shared.sdk.set(labels: ["item3": "playstation 4", "itemPrice": 400])
        case .modalPresentation:
            let modalViewController = ModalViewController()
            modalViewController.modalPresentationStyle = .fullScreen
            present(modalViewController, animated: true)
        case .segmentedCollectionView:
            navigationController?.pushViewController(SegmentedCollectionViewController(), animated: true)
        case .sendCrash:
            CrashSim.simulateRandomCrash()
        case .shutDownCoralogixRum:
            CoralogixRumManager.shared.sdk.shutdown()
        default:
            break
        }
    }

    // tvOS has no touch highlight; the focus engine is the only selection feedback.
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
