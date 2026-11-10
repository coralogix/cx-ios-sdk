//
//  CrashLabViewController.swift
//  DemoAppSwift
//
//  The Crash Lab: launch settings (applied at the next launch) and every case of
//  `crash-lab/cases.json`, each with what to check and, when it has one, its trigger. Mirrors
//  `CrashLabView` in the SwiftUI demo app; both run the shared `CrashLabTriggers`.
//

import UIKit

final class CrashLabViewController: UITableViewController {
    private let settings = CrashLabSettings.shared
    private let sections = CrashLabCatalog.sections

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Crash Lab"
        tableView.accessibilityIdentifier = "crashLab.list"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        // Every case id the screen lists, for the UI test that compares it with the file.
        let ids = UILabel()
        ids.isAccessibilityElement = true
        ids.accessibilityIdentifier = "crashLab.caseIds"
        ids.accessibilityValue = CrashLabCatalog.allIds
        ids.text = "\(CrashLabCatalog.cases.count) cases · settings apply at the next launch"
        ids.font = .preferredFont(forTextStyle: .footnote)
        ids.textColor = .secondaryLabel
        ids.textAlignment = .center
        ids.frame = CGRect(x: 0, y: 0, width: 0, height: 36)
        tableView.tableHeaderView = ids
    }

    // MARK: - Data

    /// Section 0 holds a reset row, then the settings; the cases follow, one section per section name.
    override func numberOfSections(in tableView: UITableView) -> Int {
        1 + sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? CrashLabSetting.allCases.count + 1 : sections[section - 1].cases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Launch settings" : sections[section - 1].name
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0
        cell.detailTextLabel?.textColor = .secondaryLabel

        if indexPath.section == 0 {
            if indexPath.row == 0 {
                cell.textLabel?.text = "Reset every setting"
                cell.textLabel?.textColor = .systemRed
                cell.accessibilityIdentifier = "crashLab.reset"
                return cell
            }
            let setting = CrashLabSetting.allCases[indexPath.row - 1]
            let value = settings[setting].description
            cell.textLabel?.text = setting.label
            cell.detailTextLabel?.text = value
            cell.accessibilityIdentifier = "crashLab.setting.\(setting.key)"
            cell.accessibilityValue = value
            return cell
        }

        let labCase = sections[indexPath.section - 1].cases[indexPath.row]
        cell.textLabel?.text = "\(labCase.id) · \(labCase.title)"
        cell.detailTextLabel?.text = labCase.detail
        cell.accessibilityIdentifier = "crashLab.case.\(labCase.id)"
        cell.accessoryType = labCase.isRunnable ? .detailButton : .none
        cell.selectionStyle = labCase.isRunnable ? .default : .none
        return cell
    }

    // MARK: - Actions

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            if indexPath.row == 0 {
                settings.reset()
            } else {
                settings.cycle(CrashLabSetting.allCases[indexPath.row - 1])
            }
            tableView.reloadSections(IndexSet(integer: 0), with: .none)
            return
        }
        let labCase = sections[indexPath.section - 1].cases[indexPath.row]
        guard labCase.isRunnable, let trigger = labCase.trigger else { return }
        if let message = CrashLabTriggers.run(trigger) {
            let alert = UIAlertController(title: labCase.id, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}
