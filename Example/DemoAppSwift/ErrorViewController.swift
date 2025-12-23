//
//  ErrorViewController.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 20/08/2024.
//
import UIKit
import Coralogix

final class ErrorViewController: UITableViewController {

    private struct ErrorItem {
        let title: String
        let subtitle: String
        let systemImageName: String
        let key: Keys
    }

    // MARK: - Data

    private lazy var items: [ErrorItem] = [
        .init(
            title: "NSException",
            subtitle: "Send NSException error",
            systemImageName: "exclamationmark.triangle",
            key: .sendNSException
        ),
        .init(
            title: "NSError",
            subtitle: "Send NSError error",
            systemImageName: "exclamationmark.circle",
            key: .sendNSError
        ),
        .init(
            title: "Error",
            subtitle: "Send Swift Error",
            systemImageName: "xmark.circle",
            key: .sendError
        ),
        .init(
            title: "Message Data Error",
            subtitle: "Custom log with error message",
            systemImageName: "doc.text",
            key: .sendMessageDataError
        ),
        .init(
            title: "Stack Trace Error",
            subtitle: "Error with stack trace and type",
            systemImageName: "list.bullet.rectangle",
            key: .sendMessageStackTraceTypeIsCarshError
        ),
        .init(
            title: "Log Error",
            subtitle: "Send error via logging",
            systemImageName: "doc.append",
            key: .sendLogError
        ),
        .init(
            title: "Crash",
            subtitle: "Simulate a random crash",
            systemImageName: "bolt.trianglebadge.exclamationmark",
            key: .sendCrash
        ),
        .init(
            title: "Simulate ANR",
            subtitle: "Application Not Responding",
            systemImageName: "hourglass",
            key: .simulateANR
        )
    ]

    // MARK: - Init

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavigationBar()
        setupTableView()
    }

    // MARK: - UI Setup

    private func setupNavigationBar() {
        title = "Error instrumentation"
        navigationController?.navigationBar.prefersLargeTitles = true
    }

    private func setupTableView() {
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "error_cell")
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 56, bottom: 0, right: 16)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView,
                            numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "error_cell", for: indexPath)

        var config = UIListContentConfiguration.subtitleCell()
        config.text = item.title
        config.secondaryText = item.subtitle
        config.image = UIImage(systemName: item.systemImageName)
        config.imageProperties.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        config.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
        config.secondaryTextProperties.color = .secondaryLabel

        cell.contentConfiguration = config
        cell.accessoryType = .none
        cell.selectionStyle = .default

        return cell
    }

    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView,
                            didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        showToast("Selected: \(item.title)")

        switch item.key {
        case .sendNSException:
            ErrorSim.sendNSException()

        case .sendNSError:
            ErrorSim.sendNSError()

        case .sendError:
            ErrorSim.sendError()

        case .sendMessageDataError:
            ErrorSim.sendMessageDataError()

        case .sendMessageStackTraceTypeIsCarshError:
            ErrorSim.sendMessageStackTraceTypeIsCarshError()

        case .sendLogError:
            ErrorSim.sendErrorLog()

        case .sendCrash:
            CrashSim.simulateRandomCrash()

        case .simulateANR:
            ErrorSim.simulateANR()

        default:
            break
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        let toastLabel = UILabel()
        toastLabel.text = message
        toastLabel.textColor = .white
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toastLabel.textAlignment = .center
        toastLabel.font = .preferredFont(forTextStyle: .subheadline)
        toastLabel.numberOfLines = 0
        toastLabel.alpha = 0.0
        toastLabel.layer.cornerRadius = 12
        toastLabel.layer.masksToBounds = true

        let horizontalScreenMargin: CGFloat = 24
        let horizontalTextPadding: CGFloat = 32
        let verticalTextPadding: CGFloat = 24
        let bottomMargin: CGFloat = 16
        let maxToastHeight: CGFloat = 100

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {

            let maxWidth = keyWindow.bounds.width - 2 * horizontalScreenMargin
            let expectedSize = toastLabel.sizeThatFits(CGSize(width: maxWidth, height: maxToastHeight))
            let width = min(maxWidth, expectedSize.width + horizontalTextPadding)
            let height = expectedSize.height + verticalTextPadding

            toastLabel.frame = CGRect(
                x: (keyWindow.bounds.width - width) / 2,
                y: keyWindow.bounds.height - keyWindow.safeAreaInsets.bottom - height - bottomMargin,
                width: width,
                height: height
            )

            keyWindow.addSubview(toastLabel)
            UIView.animate(withDuration: 0.3, animations: { toastLabel.alpha = 1.0 })

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                UIView.animate(withDuration: 0.3, animations: { toastLabel.alpha = 0.0 }) { _ in
                    toastLabel.removeFromSuperview()
                }
            }
        }
    }
}

