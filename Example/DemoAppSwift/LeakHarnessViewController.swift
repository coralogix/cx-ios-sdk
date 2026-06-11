//
//  LeakHarnessViewController.swift
//  DemoAppSwift
//
//  BUGV2-6045 native-iOS session-replay leak harness host controller.
//  Only reachable when the app is launched with `--leak-harness` —
//  see SceneDelegate. Mirrors the native-Android LeakHarnessActivity:
//  a vertical list of [label | masked magenta sentinel] rows that
//  exposes the frame-skew bug under slow scroll with maskText.
//

import UIKit

/// Per-run entropy + sentinel format for the leak harness.
///
/// Sentinel format is shared across all Coralogix SDK leak harnesses
/// (Flutter, native iOS, native Android, RN). Normative spec is in
/// `docs/session-replay-shared.md` §5 in the cx-flutter-plugin repo:
///
///     MASK_LEAK_<scenario>_<index>_<entropy>
///
/// Sentinel pixels are pure magenta (#FF00FF). The host-side pixel
/// scanner counts pixels matching that color in each captured frame.
/// Any non-zero count is a leak.
enum LeakHarnessSentinel {
    /// Entropy is generated once per process. Each launch is a fresh
    /// run — no need to persist across launches.
    static let entropy: String = {
        var s = ""
        for _ in 0..<8 {
            s.append(String(format: "%x", Int.random(in: 0..<16)))
        }
        return s
    }()

    static func string(scenario: String, index: Int) -> String {
        let s = scenario.uppercased()
        let i = String(format: "%04d", index)
        return "MASK_LEAK_\(s)_\(i)_\(entropy)"
    }
}

/// Hosts a UITableView with sentinel rows for the LIST slow-scroll
/// scenario. The UITableView has a stable accessibility identifier so
/// the XCUITest can find it for drag actions.
final class LeakHarnessViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    static let tableAccessibilityIdentifier = "cx_leak_harness_table"

    private let scenario: String
    private let itemCount: Int

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .white
        table.separatorStyle = .none
        table.rowHeight = 44
        table.dataSource = self
        table.delegate = self
        table.register(SentinelCell.self, forCellReuseIdentifier: SentinelCell.reuseId)
        table.accessibilityIdentifier = LeakHarnessViewController.tableAccessibilityIdentifier
        return table
    }()

    init(scenario: String = "LIST", itemCount: Int = 200) {
        self.scenario = scenario
        self.itemCount = itemCount
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return itemCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SentinelCell.reuseId, for: indexPath) as! SentinelCell
        cell.bind(label: "Item \(indexPath.row)",
                  sentinel: LeakHarnessSentinel.string(scenario: scenario, index: indexPath.row))
        return cell
    }
}

/// Card-style row mirroring the production-leak screenshot shape:
/// `[ "Item N" label (visible) | sentinel value (MAGENTA, masked) ]`.
///
/// The sentinel label has `cxMask = true` set directly — mask rect
/// equals the text rect (no padding inflation). Same layout choice as
/// the Android `SentinelAdapter` (see project memory
/// `leak_detection_via_pixel_color`): tight masks expose the
/// frame-skew bug cleanly during scroll; padded masks hide it.
private final class SentinelCell: UITableViewCell {
    static let reuseId = "SentinelCell"

    private let labelView = UILabel()
    private let sentinelView = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.backgroundColor = .white

        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.font = .systemFont(ofSize: 16)
        labelView.textColor = UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)
        contentView.addSubview(labelView)

        sentinelView.translatesAutoresizingMaskIntoConstraints = false
        sentinelView.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .bold)
        sentinelView.textColor = UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)
        sentinelView.textAlignment = .right
        contentView.addSubview(sentinelView)

        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            labelView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            sentinelView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            sentinelView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            sentinelView.leadingAnchor.constraint(greaterThanOrEqualTo: labelView.trailingAnchor, constant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func bind(label: String, sentinel: String) {
        labelView.text = label
        sentinelView.text = sentinel
    }
}

// MARK: - Navigation transition scenario (BUGV2-6045)
//
// Two screens, each carrying sentinel labels (cxMask=true, magenta text).
// The XCUITest rapidly pushes/pops between them; session-replay frames
// captured mid-animation should still have the exiting screen's sentinels
// masked. Any unmasked magenta pixel in those frames is a leak.
//
// Screen A — scenario "NAVIGATE_A"
// Screen B — scenario "NAVIGATE_B"

// MARK: Screen A

final class NavigationLeakScreenA: UIViewController {
    static let pushButtonId = "cx_leak_nav_push"
    private static let sentinelCount = 8

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Screen A"
        // Suppress back-button text so only the < chevron shows on Screen B.
        // The chevron is a system image (not magenta), so it doesn't register
        // as a leak. This keeps the harness honest without false-positives from
        // system UI we can't mask.
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain,
                                                           target: nil, action: nil)
        view.backgroundColor = .white

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        for i in 0..<Self.sentinelCount {
            stack.addArrangedSubview(makeSentinelRow(
                label: "A-Item \(i)",
                sentinel: LeakHarnessSentinel.string(scenario: "NAVIGATE_A", index: i)
            ))
        }

        let pushButton = UIButton(type: .system)
        pushButton.setTitle("Push Screen B", for: .normal)
        pushButton.setTitleColor(UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0), for: .normal)
        pushButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        pushButton.accessibilityIdentifier = Self.pushButtonId
        pushButton.addTarget(self, action: #selector(pushB), for: .touchUpInside)
        pushButton.translatesAutoresizingMaskIntoConstraints = false
        pushButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

        stack.addArrangedSubview(pushButton)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.magenta]
    }

    @objc private func pushB() {
        navigationController?.pushViewController(NavigationLeakScreenB(), animated: true)
    }
}

// MARK: Screen B

final class NavigationLeakScreenB: UIViewController {
    static let popButtonId = "cx_leak_nav_pop"
    private static let sentinelCount = 8

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Screen B"
        // Slightly different background so a human watching the test can tell
        // which screen is on-screen at any moment.
        view.backgroundColor = UIColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        for i in 0..<Self.sentinelCount {
            stack.addArrangedSubview(makeSentinelRow(
                label: "B-Item \(i)",
                sentinel: LeakHarnessSentinel.string(scenario: "NAVIGATE_B", index: i)
            ))
        }

        let popButton = UIButton(type: .system)
        popButton.setTitle("Go Back", for: .normal)
        popButton.setTitleColor(UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0), for: .normal)
        popButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        popButton.accessibilityIdentifier = Self.popButtonId
        popButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        popButton.translatesAutoresizingMaskIntoConstraints = false
        popButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

        stack.addArrangedSubview(popButton)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - Shared helpers

/// Horizontal sentinel row reused by both navigation-scenario screens.
/// Left side: visible label. Right side: magenta cxMask sentinel.
/// Layout mirrors SentinelCell so the mask geometry is identical to the
/// scroll-list scenario and the pixel scanner needs no extra config.
private func makeSentinelRow(label: String, sentinel: String) -> UIView {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.heightAnchor.constraint(equalToConstant: 44).isActive = true

    let labelView = UILabel()
    labelView.translatesAutoresizingMaskIntoConstraints = false
    labelView.font = .systemFont(ofSize: 16)
    labelView.textColor = UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)
    labelView.text = label

    let sentinelView = UILabel()
    sentinelView.translatesAutoresizingMaskIntoConstraints = false
    sentinelView.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .bold)
    sentinelView.textColor = UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)
    sentinelView.textAlignment = .right
    sentinelView.text = sentinel

    container.addSubview(labelView)
    container.addSubview(sentinelView)

    NSLayoutConstraint.activate([
        labelView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
        labelView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        sentinelView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        sentinelView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        sentinelView.leadingAnchor.constraint(greaterThanOrEqualTo: labelView.trailingAnchor, constant: 8),
    ])
    return container
}
