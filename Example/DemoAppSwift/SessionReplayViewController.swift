import UIKit
import Coralogix

class SessionReplayViewController: UITableViewController {

    let items = [
        Keys.startRecoding.rawValue,
        Keys.stopRecoding.rawValue,
        Keys.captureEvent.rawValue,
        Keys.isRecording.rawValue,
        Keys.isInitialized.rawValue,
        Keys.updateSessionId.rawValue,
        Keys.creditCardElement.rawValue,
        Keys.registerMaskRegion.rawValue,
        Keys.unregisterMaskRegion.rawValue,
        Keys.creditCardImgElement.rawValue,
        Keys.creditCardImgElement.rawValue,
        Keys.creditCardImgElement.rawValue,
        Keys.creditCardImgElement.rawValue,
        Keys.creditCardImgElement.rawValue
    ]

    let images = ["master.png", "testImg2.png", "american.png", "visa.png", "testImg.png"]
    var customView = CustomView(frame: .zero)
    private let customViewHeight: CGFloat = 150

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Session Replay"
        navigationController?.navigationBar.prefersLargeTitles = false

        // Very “native” feel
        view.backgroundColor = .systemGroupedBackground
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 56, bottom: 0, right: 16)
        tableView.showsVerticalScrollIndicator = true
        tableView.contentInset = .zero

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "session_replay_cell")
        tableView.register(CreditCardInputCell.self, forCellReuseIdentifier: "CreditCardInputCell")
        tableView.register(FullImageCell.self, forCellReuseIdentifier: "full_image_cell")

        tableView.dataSource = self
        tableView.delegate = self

        tableView.tableHeaderView = makeHeaderView()
    }

    // MARK: - Header

    private func makeHeaderView() -> UIView {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.text = "Quick controls for Session Replay recording, masking and events."
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel

        let container = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 0))
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        container.layoutIfNeeded()
        return container
    }

    // MARK: - Data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellText = items[indexPath.row]

        if cellText == Keys.creditCardElement.rawValue {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "CreditCardInputCell",
                for: indexPath
            ) as? CreditCardInputCell else {
                return UITableViewCell()
            }
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            return cell

        } else if cellText == Keys.creditCardImgElement.rawValue {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "full_image_cell",
                for: indexPath
            ) as? FullImageCell else {
                return UITableViewCell()
            }
            if let randomImage = images.randomElement() {
                cell.configure(with: randomImage)
            }
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: "session_replay_cell",
                for: indexPath
            )

            var content = UIListContentConfiguration.subtitleCell()
            content.text = prettyTitle(for: cellText)
            content.secondaryText = subtitle(for: cellText)
            content.secondaryTextProperties.color = .secondaryLabel
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)

            if let iconName = iconName(for: cellText) {
                content.image = UIImage(systemName: iconName)
                content.imageProperties.tintColor = view.tintColor
                content.imageProperties.preferredSymbolConfiguration =
                    UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            }

            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default

            // Use system background for cells (works in light & dark)
            cell.backgroundColor = .secondarySystemGroupedBackground

            return cell
        }
    }

    // MARK: - Delegate

    override func tableView(_ tableView: UITableView,
                            didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        customView.updateText("Selected item: \(item)")

        if item == Keys.startRecoding.rawValue {
            CoralogixRumManager.shared.sdk.startRecording()
        } else if item == Keys.stopRecoding.rawValue {
            CoralogixRumManager.shared.sdk.stopRecording()
        } else if item == Keys.captureEvent.rawValue {
            CoralogixRumManager.shared.sdk.captureEvent()
        } else if item == Keys.updateSessionId.rawValue {
            CoralogixRumManager.shared.sdk.update(sessionId: UUID().uuidString.lowercased())
        } else if item == Keys.isRecording.rawValue {
            showAlertView(message: "isRecording: \(CoralogixRumManager.shared.sdk.isSRRecording())")
        } else if item == Keys.isInitialized.rawValue {
            showAlertView(message: "isInitialized: \(CoralogixRumManager.shared.sdk.isSRInitialized())")
        } else if item == Keys.registerMaskRegion.rawValue {
            let maskRegionId = "demoMaskRegion"
            CoralogixRumManager.shared.sdk.registerMaskRegion(maskRegionId)
            showAlertView(message: "Registered mask region with id: \(maskRegionId)")
        } else if item == Keys.unregisterMaskRegion.rawValue {
            let maskRegionId = "demoMaskRegion"
            CoralogixRumManager.shared.sdk.unregisterMaskRegion(maskRegionId)
            showAlertView(message: "Unregistered mask region with id: \(maskRegionId)")
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    override func tableView(_ tableView: UITableView,
                            heightForRowAt indexPath: IndexPath) -> CGFloat {
        let cellText = items[indexPath.row]
        if cellText == Keys.creditCardImgElement.rawValue {
            return 150
        }
        return UITableView.automaticDimension
    }

    // MARK: - Alerts

    public func showAlertView(message: String) {
        let alert = UIAlertController(title: "Alert", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Helpers

    private func prettyTitle(for raw: String) -> String {
        switch raw {
        case Keys.startRecoding.rawValue:      return "Start Recording"
        case Keys.stopRecoding.rawValue:       return "Stop Recording"
        case Keys.captureEvent.rawValue:       return "Capture Event"
        case Keys.isRecording.rawValue:        return "Is Recording?"
        case Keys.isInitialized.rawValue:      return "Is Initialized?"
        case Keys.updateSessionId.rawValue:    return "Update Session ID"
        case Keys.registerMaskRegion.rawValue: return "Register Mask Region"
        case Keys.unregisterMaskRegion.rawValue: return "Unregister Mask Region"
        default: return raw
        }
    }

    private func subtitle(for raw: String) -> String {
        switch raw {
        case Keys.startRecoding.rawValue:
            return "Begin capturing user interactions for this session."
        case Keys.stopRecoding.rawValue:
            return "Stop recording and finalize the current session."
        case Keys.captureEvent.rawValue:
            return "Manually send a custom event to Session Replay."
        case Keys.isRecording.rawValue:
            return "Check if Session Replay is currently recording."
        case Keys.isInitialized.rawValue:
            return "Check if the SDK has been initialized."
        case Keys.updateSessionId.rawValue:
            return "Generate and apply a fresh session identifier."
        case Keys.registerMaskRegion.rawValue:
            return "Mask a region of the screen from recording."
        case Keys.unregisterMaskRegion.rawValue:
            return "Remove the mask from the demo region."
        default:
            return ""
        }
    }

    private func iconName(for raw: String) -> String? {
        switch raw {
        case Keys.startRecoding.rawValue:      return "record.circle"
        case Keys.stopRecoding.rawValue:       return "stop.circle"
        case Keys.captureEvent.rawValue:       return "sparkles"
        case Keys.isRecording.rawValue:        return "waveform.circle"
        case Keys.isInitialized.rawValue:      return "checkmark.seal"
        case Keys.updateSessionId.rawValue:    return "arrow.triangle.2.circlepath"
        case Keys.registerMaskRegion.rawValue: return "eye.slash"
        case Keys.unregisterMaskRegion.rawValue: return "eye"
        default: return nil
        }
    }
}
