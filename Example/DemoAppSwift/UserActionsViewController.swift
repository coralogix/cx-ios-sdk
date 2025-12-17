//
//  UserActionsViewController.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 20/08/2024.
//

import UIKit

final class UserActionsViewController: UITableViewController {

    enum Keys {
        case modalPresentation
        case segmentedCollectionView
        case pageController
        case alertView
        case simulateCrashBadAccess
        case simulateCrashFatalError
    }

    // MARK: - Item Model

    struct Item {
        let key: Keys
        let title: String
        let subtitle: String
        let systemImageName: String
    }

    private let items: [Item] = [
        .init(
            key: .modalPresentation,
            title: "Modal Presentation",
            subtitle: "Track full-screen modals and presentation flows",
            systemImageName: "rectangle.on.rectangle"
        ),
        .init(
            key: .segmentedCollectionView,
            title: "Segmented Collection",
            subtitle: "Monitor segmented controls & collection interactions",
            systemImageName: "square.grid.2x2"
        ),
        .init(
            key: .pageController,
            title: "Page Controller",
            subtitle: "Capture page swipes and transitions",
            systemImageName: "rectangle.portrait.on.rectangle.portrait"
        ),
        .init(
            key: .alertView,
            title: "Alert View",
            subtitle: "Instrument alerts and user confirmations",
            systemImageName: "exclamationmark.triangle"
        ),
        .init(
            key: .simulateCrashBadAccess,
            title: "Simulate Crash: Bad Access",
            subtitle: "Trigger an EXC_BAD_ACCESS crash for testing",
            systemImageName: "xmark.octagon.fill"
        ),
        .init(
            key: .simulateCrashFatalError,
            title: "Simulate Crash: Fatal Error",
            subtitle: "Trigger a fatalError() crash for testing",
            systemImageName: "xmark.octagon"
        )
    ]

    // MARK: - Constants

    private static let cellIdentifier = "user_actions_cell"

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavigationBar()
        setupTableView()
    }

    // MARK: - UI Setup

    private func setupNavigationBar() {
        title = "User Actions"
        navigationController?.navigationBar.prefersLargeTitles = true
    }

    private func setupTableView() {
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 56, bottom: 0, right: 16)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)

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
        case .modalPresentation:
            let modalViewController = ModalViewController()
            modalViewController.modalPresentationStyle = .fullScreen
            present(modalViewController, animated: true, completion: nil)

        case .segmentedCollectionView:
            let segmentedCollectionViewController = SegmentedCollectionViewController()
            navigationController?.pushViewController(segmentedCollectionViewController, animated: true)

        case .pageController:
            let pageController = PageController()
            navigationController?.pushViewController(pageController, animated: true)

        case .alertView:
            let alert = UIAlertController(
                title: "Alert",
                message: "I'm an alert",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.showToast("Alert dismissed")
            })
            present(alert, animated: true)

        case .simulateCrashBadAccess:
            simulateCrashWithFirstResponder()
        case .simulateCrashFatalError:
            simulateCrashWithFatalError()
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: - Crash Simulation

    /// Simulates a crash by forcing an EXC_BAD_ACCESS
    private func simulateCrashWithFirstResponder() {
        // Show confirmation alert before crashing
        let alert = UIAlertController(
            title: "⚠️ Simulate Crash",
            message: "This will crash the app to test crash reporting. Continue?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.showToast("Crash cancelled")
        })

        alert.addAction(UIAlertAction(title: "Crash Now", style: .destructive) { [weak self] _ in
            self?.showToast("Crashing app...")

            // Delay slightly so user can see the message
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Simulate EXC_BAD_ACCESS by accessing deallocated memory
                // This creates a crash that looks like it came from findFirstResponder
                self?.triggerBadAccessCrash()
            }
        })

        present(alert, animated: true)
    }
    
    /// Simulates a crash by calling fatalError()
    private func simulateCrashWithFatalError() {
        let alert = UIAlertController(
            title: "⚠️ Simulate Fatal Error Crash",
            message: "This will crash the app using fatalError(). Continue?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.showToast("Crash cancelled")
        })
        alert.addAction(UIAlertAction(title: "Crash Now", style: .destructive) { _ in
            fatalError("Simulated crash (fatalError)")
        })
        present(alert, animated: true)
    }
    
    /// Triggers an EXC_BAD_ACCESS crash that appears to come from UIView.findFirstResponder
    private func triggerBadAccessCrash() {
        // Method 1: Call via Objective-C runtime to make it appear in stack trace
        let selector = NSSelectorFromString("_findFirstResponder")
        if UIView.responds(to: selector) {
            // If method exists (it shouldn't), call it
            UIView.perform(selector)
        } else {
            // Force the crash to appear from a UIView method call
            simulateUIViewFindFirstResponder()
        }
    }
    
    @objc private func simulateUIViewFindFirstResponder() {
        // This creates the crash with method name in stack trace
        // Use KERN_PROTECTION_FAILURE to match the screenshot
        let pointer = UnsafeMutablePointer<Int>(bitPattern: 0x16)!
        pointer.pointee = 42
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

