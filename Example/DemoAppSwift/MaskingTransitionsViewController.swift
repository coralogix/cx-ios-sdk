import UIKit

// UIKit mirror of MaskingTransitionsView. UIKit text is masked through the
// deterministic view-walk path (collectTextViewRects), not the Vision-OCR path
// used for SwiftUI/Flutter — so this screen acts as the control: if the OCR
// path leaks during a bottom sheet / back transition while this one does not,
// the defect is in the OCR pipeline.
//
// Launch with `--mask-all-text` to record with maskText [".*"], then present
// the bottom sheet and swipe back from the detail screen and inspect the saved
// frames in the simulator's Documents/sessionreplay folder.
final class MaskingTransitionsViewController: UITableViewController {

    private struct Customer {
        let name: String
        let email: String
        let card: String
    }

    private enum Row {
        case presentSheet
        case pushDetail
    }

    private let actions: [Row] = [.presentSheet, .pushDetail]

    private let customers: [Customer] = [
        .init(name: "Olivia Bennett", email: "olivia.bennett@example.com", card: "4539 8842 1190 5567"),
        .init(name: "Liam Carter", email: "liam.carter@example.com", card: "5221 7741 0098 2231"),
        .init(name: "Sofia Rossi", email: "sofia.rossi@example.com", card: "6011 3387 4452 1009"),
        .init(name: "Noah Schmidt", email: "noah.schmidt@example.com", card: "4024 0071 5523 8890"),
        .init(name: "Emma Dubois", email: "emma.dubois@example.com", card: "3782 822463 10005"),
        .init(name: "Kenji Tanaka", email: "kenji.tanaka@example.com", card: "4716 9921 7745 3320"),
        .init(name: "Aisha Khan", email: "aisha.khan@example.com", card: "5412 7556 1187 4432"),
        .init(name: "Lucas Silva", email: "lucas.silva@example.com", card: "6011 5523 8841 9090"),
        .init(name: "Mia Andersen", email: "mia.andersen@example.com", card: "4485 2299 0071 6654"),
        .init(name: "Daniel Cohen", email: "daniel.cohen@example.com", card: "5105 1051 0510 5100"),
        .init(name: "Chloe Martin", email: "chloe.martin@example.com", card: "4111 1111 1111 1111"),
        .init(name: "Hiroshi Sato", email: "hiroshi.sato@example.com", card: "3530 1113 3330 0000"),
        .init(name: "Isabella Costa", email: "isabella.costa@example.com", card: "6011 0009 9013 9424"),
        .init(name: "Ethan Wright", email: "ethan.wright@example.com", card: "4012 8888 8888 1881"),
        .init(name: "Yara Haddad", email: "yara.haddad@example.com", card: "5555 5555 5555 4444")
    ]

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Masking Transitions"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "customer")
    }

    // MARK: - Data source

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Transitions" : "Customer Records"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? actions.count : customers.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            var config = UIListContentConfiguration.subtitleCell()
            switch actions[indexPath.row] {
            case .presentSheet:
                config.text = "Present Bottom Sheet"
                config.secondaryText = "Sensitive text over the list"
                config.image = UIImage(systemName: "rectangle.bottomthird.inset.filled")
            case .pushDetail:
                config.text = "Push Detail Screen"
                config.secondaryText = "Swipe back to test the back transition"
                config.image = UIImage(systemName: "chevron.right.circle")
            }
            config.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "customer", for: indexPath)
        let customer = customers[indexPath.row]
        var config = UIListContentConfiguration.subtitleCell()
        config.text = customer.name
        config.secondaryText = "\(customer.email)\n\(customer.card)"
        config.secondaryTextProperties.numberOfLines = 2
        config.secondaryTextProperties.color = .secondaryLabel
        config.image = UIImage(systemName: "person.crop.circle.fill")
        config.imageProperties.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        return cell
    }

    // MARK: - Delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0 else { return }
        switch actions[indexPath.row] {
        case .presentSheet:
            presentBottomSheet()
        case .pushDetail:
            navigationController?.pushViewController(MaskingTransitionsDetailViewController(), animated: true)
        }
    }

    private func presentBottomSheet() {
        let sheet = MaskingTransitionsSheetViewController()
        let nav = UINavigationController(rootViewController: sheet)
        if #available(iOS 15.0, *), let presentation = nav.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }
}

// Bottom-sheet content with sensitive text fields and labels.
final class MaskingTransitionsSheetViewController: UITableViewController {

    private let rows: [(String, String)] = [
        ("Cardholder", "Olivia Bennett"),
        ("Card Number", "4539 8842 1190 5567"),
        ("Expiry", "08 / 27"),
        ("CVV", "123"),
        ("Street", "42 Riverside Lane"),
        ("City", "Manchester"),
        ("Postcode", "M1 4AB")
    ]

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Checkout"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(dismissSheet))
    }

    @objc private func dismissSheet() {
        dismiss(animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let row = rows[indexPath.row]
        var config = UIListContentConfiguration.valueCell()
        config.text = row.0
        config.secondaryText = row.1
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        return cell
    }
}

// Detail screen for exercising the interactive back ("back move") transition.
final class MaskingTransitionsDetailViewController: UIViewController {

    private let fields: [(String, String)] = [
        ("Full Name", "Olivia Bennett"),
        ("Email", "olivia.bennett@example.com"),
        ("Phone", "+44 7700 900123"),
        ("National ID", "QQ 12 34 56 C"),
        ("IBAN", "GB29 NWBK 6016 1331 9268 19"),
        ("Card", "4539 8842 1190 5567")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Account Detail"
        view.backgroundColor = .systemGroupedBackground

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let note = UILabel()
        note.text = "Swipe from the left edge to pop this screen. A frame captured " +
                    "mid-transition is the one to inspect for un-masked text."
        note.font = .preferredFont(forTextStyle: .footnote)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        stack.addArrangedSubview(note)

        for (title, value) in fields {
            let label = UILabel()
            label.numberOfLines = 0
            label.attributedText = row(title: title, value: value)
            stack.addArrangedSubview(label)
        }

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])
    }

    private func row(title: String, value: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: "\(title): ",
            attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline),
                         .foregroundColor: UIColor.secondaryLabel])
        result.append(NSAttributedString(
            string: value,
            attributes: [.font: UIFont.monospacedSystemFont(ofSize: 15, weight: .medium),
                         .foregroundColor: UIColor.label]))
        return result
    }
}
