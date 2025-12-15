import UIKit
import Coralogix
import MetricKit

final class MainViewController: UITableViewController {

    private struct MenuItem {
        let title: String
        let subtitle: String
        let systemImageName: String
        let key: Keys
    }

    // MARK: - Data

    private lazy var items: [MenuItem] = [
        .init(
            title: "Network instrumentation",
            subtitle: "Track requests, responses & timings",
            systemImageName: "antenna.radiowaves.left.and.right",
            key: .networkInstumentation
        ),
        .init(
            title: "Error instrumentation",
            subtitle: "Capture crashes, errors & exceptions",
            systemImageName: "exclamationmark.triangle",
            key: .errorInstumentation
        ),
        .init(
            title: "SDK functions",
            subtitle: "Test core Coralogix APIs",
            systemImageName: "gearshape",
            key: .sdkFunctions
        ),
        .init(
            title: "User actions",
            subtitle: "Buttons, screens & custom events",
            systemImageName: "hand.tap",
            key: .userActionsInstumentation
        ),
        .init(
            title: "Session replay",
            subtitle: "Replay user sessions visually",
            systemImageName: "film.stack",
            key: .sessionReplay
        ),
        .init(
            title: "Clock",
            subtitle: "Timing, spans & scheduling",
            systemImageName: "clock",
            key: .clock
        ),
        .init(
            title: "Schema validation",
            subtitle: "Validate payload structure & fields",
            systemImageName: "checkmark.shield",
            key: .schemaValidation
        ),
        .init(
            title: "Mask UI",
            subtitle: "Hide sensitive on-screen data",
            systemImageName: "eye.slash",
            key: .maskUI
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
        setupHeaderView()
        setupCopyButton()
    }

    // MARK: - UI Setup

    private func setupNavigationBar() {
        navigationItem.title = "Coralogix Demo"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationController?.navigationBar.tintColor = .systemBlue
    }

    private func setupTableView() {
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 56, bottom: 0, right: 16)
    }

    private func setupHeaderView() {
        let sessionID = CoralogixRumManager.shared.getSessionId()?.lowercased() ?? "No session"

        let container = UIView()
        container.backgroundColor = .clear

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14
        card.layer.masksToBounds = true

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Session ID"
        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .secondaryLabel

        let valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.text = sessionID
        valueLabel.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        valueLabel.textColor = .label
        valueLabel.numberOfLines = 2

        let copyButton = UIButton(type: .system)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.setTitle("Copy", for: .normal)
        copyButton.addTarget(self, action: #selector(copySessionIDToClipboard), for: .touchUpInside)

        card.addSubview(titleLabel)
        card.addSubview(valueLabel)
        card.addSubview(copyButton)
        container.addSubview(card)

        let layoutMargins: CGFloat = 16

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: layoutMargins),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -layoutMargins),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: copyButton.leadingAnchor, constant: -8),

            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            valueLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            valueLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            copyButton.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12)
        ])

        // Size header explicitly
        let headerWidth = view.bounds.width
        container.frame = CGRect(x: 0, y: 0, width: headerWidth, height: 80)
        tableView.tableHeaderView = container
    }

    private func setupCopyButton() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "doc.on.doc"),
            style: .plain,
            target: self,
            action: #selector(copySessionIDToClipboard)
        )
    }

    // MARK: - Actions

    @objc private func copySessionIDToClipboard() {
        guard let sessionID = CoralogixRumManager.shared.getSessionId() else {
            showToast("No session ID available")
            return
        }

        UIPasteboard.general.string = sessionID
        showToast("Session ID copied")
    }

    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil,
                                      message: message,
                                      preferredStyle: .alert)
        present(alert, animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            alert.dismiss(animated: true, completion: nil)
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let item = items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)

        var config = UIListContentConfiguration.subtitleCell()
        config.text = item.title
        config.secondaryText = item.subtitle
        config.image = UIImage(systemName: item.systemImageName)
        config.imageProperties.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        config.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
        config.secondaryTextProperties.color = .secondaryLabel

        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default

        return cell
    }

    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]

        let vc: UIViewController
        switch item.key {
        case .networkInstumentation:
            vc = NetworkViewController()
        case .errorInstumentation:
            vc = ErrorViewController()
        case .sdkFunctions:
            vc = SdkViewController()
        case .userActionsInstumentation:
            vc = UserActionsViewController()
        case .sessionReplay:
            vc = SessionReplayViewController()
        case .clock:
            vc = ClockViewController()
        case .schemaValidation:
            vc = SchemaValidationViewController()
        case .maskUI:
            vc = MaskViewController()
        default:
            showToast("Not implemented for this menu item")
            return
        }

        navigationController?.pushViewController(vc, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
