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

    // Stress content for the SR text-masking pipeline: multi-language paragraphs
    // (RTL + CJK) and short non-word tokens that the old en-US + language-corrected
    // VNRecognizeTextRequest used to silently drop. Scroll through this section to
    // exercise the widened TextScanner config under maskAllTexts.
    private static let stressTextLines: [String] = [
        "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs — abc123 OK.",
        "El veloz murciélago hindú comía feliz cardillo y kiwi. La cigüeña tocaba el saxofón detrás del palenque.",
        "Portez ce vieux whisky au juge blond qui fume. Voix ambiguë d'un cœur qui préfère les jattes de kiwis.",
        "Zwölf Boxkämpfer jagen Viktor quer über den großen Sylter Deich — Größe ÄÖÜ.",
        "Ma la volpe, col suo balzo, ha raggiunto il quieto Fido — perché sì.",
        "Um pequeno jabuti xereta viu dez cegonhas felizes — coração à beça.",
        "Съешь же ещё этих мягких французских булок, да выпей чаю.",
        "דג סקרן שט לו בים זך אך לפתע פגש חבורה נחמדה של דגים.",
        "نص حكيم له سر قاطع وذو شأن عظيم مكتوب على ثوب أخضر ومغلف بجلد أزرق.",
        "いろはにほへと ちりぬるを — 価格 ¥1,200 OK 確認。",
        "敏捷的棕色狐狸跳过懒狗。今天 ¥99.90 限时特惠 OK。",
        "다람쥐 헌 쳇바퀴에 타고파. 확인 ₩9,900 OK.",
        "เป็นมนุษย์สุดประเสริฐเลิศคุณค่า กว่าบรรดาฝูงสัตว์เดรัจฉาน — OK.",
        "Ξεσκεπάζω τὴν ψυχοφθόρα βδελυγμία — Τιμή €4,99.",
        "OK · USB-C · v2.6.3 · ETA 5m · ID#A1B2 · PIN 0000",
        "$4.99 · €19,90 · £10.50 · ¥1,200 · ₪59.90 · ₹499 · ₩9,900",
        "HTTP/2 · TLS 1.3 · SHA-256 · 200 OK · 404 · 500 · 422",
        "A1B2-C3D4 · P/N: X-42 · MAC 00:1A:2B:3C:4D:5E · UUID e4f1…"
    ]

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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "stress_text_cell")

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
        2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? items.count : Self.stressTextLines.count
    }

    override func tableView(_ tableView: UITableView,
                            titleForHeaderInSection section: Int) -> String? {
        section == 1 ? "Stress Test — Mixed Text" : nil
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: "stress_text_cell",
                for: indexPath
            )
            var content = cell.defaultContentConfiguration()
            content.text = Self.stressTextLines[indexPath.row]
            content.textProperties.numberOfLines = 0
            content.textProperties.font = .preferredFont(forTextStyle: .footnote)
            cell.contentConfiguration = content
            cell.accessoryType = .none
            cell.selectionStyle = .none
            cell.backgroundColor = .secondarySystemGroupedBackground
            return cell
        }

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
        guard indexPath.section == 0 else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
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
        if indexPath.section == 1 {
            return UITableView.automaticDimension
        }
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
