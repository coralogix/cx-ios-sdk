//
//  TracesExporterViewController.swift
//  DemoAppSwift
//
//  Test view for the Traces Exporter (OTLP callback) feature.
//  UI mirrors the Flutter plugin's TracesExporterDemoPage:
//  - Copy All + Clear live in the navigation bar (top-right)
//  - Each received OTLP batch is its own expandable card row
//  - iOS-specific controls (Reinit, Trigger) are in a compact top section
//

import UIKit
import Coralogix

// MARK: - Model

private struct OtlpBatch {
    let batchNumber: Int
    let spanCount: Int
    let receivedAt: Date
    let jsonString: String
    var isExpanded: Bool = false

    var prettyJson: String {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else { return jsonString }
        return str
    }

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: receivedAt)
    }
}

// MARK: - Batch Cell

private final class OtlpBatchCell: UITableViewCell {
    var onCopy: (() -> Void)?
    var onToggle: (() -> Void)?

    private let badgeLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        l.textAlignment = .center
        l.textColor = .white
        l.backgroundColor = .systemBlue
        l.layer.cornerRadius = 8
        l.clipsToBounds = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .subheadline)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let timeLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .caption1)
        l.textColor = .secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var copyButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(didTapCopy), for: .touchUpInside)
        return b
    }()

    private lazy var expandButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(didTapToggle), for: .touchUpInside)
        return b
    }()

    // Collapsed: short preview (mirrors Flutter's 200-char, 3-line preview)
    private let previewLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        l.textColor = UIColor.secondaryLabel.withAlphaComponent(0.7)
        l.numberOfLines = 3
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // Expanded: full pretty JSON on gray background (mirrors Flutter's surfaceContainerHighest container)
    private let jsonLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        l.textColor = .secondaryLabel
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let jsonContainer: UIView = {
        let v = UIView()
        v.backgroundColor = .secondarySystemBackground
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let jsonSeparator: UIView = {
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayout() {
        let infoStack = UIStackView(arrangedSubviews: [titleLabel, timeLabel])
        infoStack.axis = .vertical
        infoStack.spacing = 2
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = UIStackView(arrangedSubviews: [badgeLabel, infoStack, copyButton, expandButton])
        headerStack.axis = .horizontal
        headerStack.spacing = 10
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        jsonContainer.addSubview(jsonSeparator)
        jsonContainer.addSubview(jsonLabel)

        contentView.addSubview(headerStack)
        contentView.addSubview(previewLabel)
        contentView.addSubview(jsonContainer)

        NSLayoutConstraint.activate([
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
            badgeLabel.heightAnchor.constraint(equalToConstant: 22),

            headerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            headerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            previewLabel.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 4),
            previewLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            previewLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            jsonContainer.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 8),
            jsonContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            jsonContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            jsonContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            jsonSeparator.topAnchor.constraint(equalTo: jsonContainer.topAnchor),
            jsonSeparator.leadingAnchor.constraint(equalTo: jsonContainer.leadingAnchor),
            jsonSeparator.trailingAnchor.constraint(equalTo: jsonContainer.trailingAnchor),
            jsonSeparator.heightAnchor.constraint(equalToConstant: 0.5),

            jsonLabel.topAnchor.constraint(equalTo: jsonSeparator.bottomAnchor, constant: 12),
            jsonLabel.leadingAnchor.constraint(equalTo: jsonContainer.leadingAnchor, constant: 16),
            jsonLabel.trailingAnchor.constraint(equalTo: jsonContainer.trailingAnchor, constant: -16),
            jsonLabel.bottomAnchor.constraint(equalTo: jsonContainer.bottomAnchor, constant: -12),
        ])
    }

    func configure(with batch: OtlpBatch) {
        badgeLabel.text = "  #\(batch.batchNumber)  "
        titleLabel.text = "\(batch.spanCount) span\(batch.spanCount == 1 ? "" : "s")"
        timeLabel.text = batch.timeString

        let preview = batch.jsonString
        previewLabel.text = preview.count > 200 ? String(preview.prefix(200)) + "…" : preview
        jsonLabel.text = batch.prettyJson

        expandButton.setImage(UIImage(systemName: batch.isExpanded ? "chevron.up" : "chevron.down"), for: .normal)
        previewLabel.isHidden = batch.isExpanded
        jsonContainer.isHidden = !batch.isExpanded
    }

    @objc private func didTapCopy() { onCopy?() }
    @objc private func didTapToggle() { onToggle?() }
}

// MARK: - View Controller

final class TracesExporterViewController: UITableViewController {

    // MARK: - Persistent state

    private static var isTracesExporterEnabled = false
    private static var batches: [OtlpBatch] = []
    private static var batchCounter = 0
    private static var fullJsonLogs: [String] = []

    // MARK: - Sections

    private enum Section: Int, CaseIterable {
        case controls = 0
        case batches  = 1
    }

    // MARK: - Lifecycle

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Traces Exporter"
        navigationController?.navigationBar.prefersLargeTitles = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "control")
        tableView.register(OtlpBatchCell.self, forCellReuseIdentifier: "batch")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "empty")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        updateNavBarButtons()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateNavBarButtons()
    }

    // MARK: - Nav bar (Copy All + Clear — mirrors Flutter AppBar actions)

    private func updateNavBarButtons() {
        guard Self.batches.isEmpty == false else {
            navigationItem.rightBarButtonItems = nil
            return
        }
        let copyBtn = UIBarButtonItem(
            image: UIImage(systemName: "doc.on.doc"),
            style: .plain,
            target: self,
            action: #selector(copyAll)
        )
        let clearBtn = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(clearBatches)
        )
        clearBtn.tintColor = .systemRed
        navigationItem.rightBarButtonItems = [clearBtn, copyBtn]
    }

    // MARK: - Table data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .controls: return 3   // Reinit, Trigger Network, Trigger Custom Span
        case .batches:  return max(Self.batches.count, 1)  // 1 = empty state row
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .controls: return nil
        case .batches:  return Self.batches.isEmpty ? nil : "Received Batches"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == Section.controls.rawValue else { return nil }
        return Self.isTracesExporterEnabled
            ? "✅ Traces Exporter enabled — \(Self.batches.count) batch(es) received"
            : "⚠️ Traces Exporter disabled — tap Reinitialize to enable"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {

        case .controls:
            let cell = tableView.dequeueReusableCell(withIdentifier: "control", for: indexPath)
            var config = UIListContentConfiguration.cell()
            switch indexPath.row {
            case 0:
                config.text = Self.isTracesExporterEnabled
                    ? "SDK initialized with Traces Exporter"
                    : "Reinitialize SDK with Traces Exporter"
                config.image = UIImage(systemName: "arrow.clockwise.circle")
                cell.accessoryType = Self.isTracesExporterEnabled ? .none : .disclosureIndicator
                cell.isUserInteractionEnabled = !Self.isTracesExporterEnabled
                config.textProperties.color = Self.isTracesExporterEnabled ? .secondaryLabel : .label
            case 1:
                config.text = "Trigger Network Request"
                config.image = UIImage(systemName: "network")
                cell.accessoryType = .disclosureIndicator
                cell.isUserInteractionEnabled = Self.isTracesExporterEnabled
                config.textProperties.color = Self.isTracesExporterEnabled ? .label : .secondaryLabel
            case 2:
                config.text = "Trigger Custom Span"
                config.image = UIImage(systemName: "point.3.connected.trianglepath.dotted")
                cell.accessoryType = .disclosureIndicator
                cell.isUserInteractionEnabled = Self.isTracesExporterEnabled
                config.textProperties.color = Self.isTracesExporterEnabled ? .label : .secondaryLabel
            default: break
            }
            cell.contentConfiguration = config
            return cell

        case .batches:
            if Self.batches.isEmpty {
                let cell = tableView.dequeueReusableCell(withIdentifier: "empty", for: indexPath)
                cell.selectionStyle = .none
                var config = UIListContentConfiguration.cell()
                config.text = "No batches yet — trigger a span above, each OTLP batch will appear here."
                config.image = UIImage(systemName: "tray")
                config.textProperties.color = .secondaryLabel
                config.textProperties.numberOfLines = 0
                config.imageProperties.tintColor = .tertiaryLabel
                cell.contentConfiguration = config
                return cell
            }
            let cell = tableView.dequeueReusableCell(withIdentifier: "batch", for: indexPath) as! OtlpBatchCell
            cell.configure(with: Self.batches[indexPath.row])
            let row = indexPath.row
            cell.onCopy = { [weak self] in self?.copyBatch(at: row) }
            cell.onToggle = { [weak self] in
                Self.batches[row].isExpanded.toggle()
                self?.tableView.reloadRows(at: [indexPath], with: .automatic)
            }
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == Section.controls.rawValue else { return }
        switch indexPath.row {
        case 0: confirmReinitialize()
        case 1: triggerNetworkRequest()
        case 2: triggerCustomSpan()
        default: break
        }
    }

    // MARK: - Actions

    private func confirmReinitialize() {
        let alert = UIAlertController(
            title: "Reinitialize SDK",
            message: "This will shutdown the current SDK and reinitialize it with the tracesExporter callback enabled.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reinitialize", style: .default) { [weak self] _ in
            self?.performReinitialize()
        })
        present(alert, animated: true)
    }

    private func performReinitialize() {
        CoralogixRumManager.shared.sdk.shutdown()

        let options = CoralogixExporterOptions(
            coralogixDomain: .EU2,
            userContext: UserContext(
                userId: "traces-exporter-test",
                userName: "Test User",
                userEmail: "test@example.com",
                userMetadata: ["test": "tracesExporter"]
            ),
            environment: "PROD",
            application: "DemoApp-iOS-TracesExporter",
            version: "1",
            publicKey: Envs.PUBLIC_KEY.rawValue,
            instrumentations: [
                .mobileVitals: true, .custom: true, .errors: true,
                .userActions: true, .network: true, .anr: true, .lifeCycle: true
            ],
            collectIPData: true,
            tracesExporter: { [weak self] data in
                let spanCount = data.spanCount
                let jsonString = data.jsonString ?? ""
                DispatchQueue.main.async {
                    Self.batchCounter += 1
                    let batch = OtlpBatch(
                        batchNumber: Self.batchCounter,
                        spanCount: spanCount,
                        receivedAt: Date(),
                        jsonString: jsonString
                    )
                    let wasEmpty = Self.batches.isEmpty
                    Self.batches.insert(batch, at: 0)
                    if !jsonString.isEmpty {
                        Self.fullJsonLogs.insert(jsonString, at: 0)
                        if Self.fullJsonLogs.count > 50 { Self.fullJsonLogs.removeLast() }
                    }
                    if Self.batches.count > 50 { Self.batches.removeLast() }

                    if wasEmpty {
                        self?.tableView.reloadSections(IndexSet(integer: Section.batches.rawValue), with: .automatic)
                    } else {
                        self?.tableView.insertRows(at: [IndexPath(row: 0, section: Section.batches.rawValue)], with: .automatic)
                    }
                    self?.tableView.reloadSections(IndexSet(integer: Section.controls.rawValue), with: .none)
                    self?.updateNavBarButtons()
                }
            },
            debug: true
        )

        CoralogixRumManager.shared.reinitialize(with: options)
        Self.isTracesExporterEnabled = true
        tableView.reloadSections(IndexSet(integer: Section.controls.rawValue), with: .automatic)
        showToast("SDK reinitialized with Traces Exporter")
    }

    private func triggerNetworkRequest() {
        guard Self.isTracesExporterEnabled else { showToast("Reinitialize SDK first"); return }
        NetworkSim.sendSuccesfullRequest()
        showToast("Network request sent")
    }

    private func triggerCustomSpan() {
        guard Self.isTracesExporterEnabled else { showToast("Reinitialize SDK first"); return }
        let rum = CoralogixRumManager.shared.sdk
        guard rum.isInitialized else { showToast("SDK not initialized"); return }
        guard let tracer = rum.getCustomTracer() else { showToast("Failed to get custom tracer"); return }
        guard let global = tracer.startGlobalSpan(
            name: "traces-exporter-test.global",
            labels: ["test.source": "TracesExporterViewController"]
        ) else { showToast("Failed to create global span"); return }
        let child = global.startCustomSpan(name: "traces-exporter-test.child")
        child.setAttribute(key: "test.attribute", value: "hello-otlp")
        child.addEvent(name: "test.event")
        child.setStatus(.ok)
        child.endSpan()
        global.endSpan()
        showToast("Custom spans created")
    }

    @objc private func copyAll() {
        guard !Self.fullJsonLogs.isEmpty else { showToast("No OTLP data to copy"); return }
        var out = "=== Traces Exporter Full Log ===\nTotal exports: \(Self.fullJsonLogs.count)\n\n"
        for (i, json) in Self.fullJsonLogs.enumerated() { out += "=== Export #\(i + 1) ===\n\(json)\n\n" }
        UIPasteboard.general.string = out
        showToast("Copied \(Self.fullJsonLogs.count) batch(es) as JSON")
    }

    @objc private func clearBatches() {
        Self.batches.removeAll()
        Self.fullJsonLogs.removeAll()
        Self.batchCounter = 0
        tableView.reloadSections(IndexSet(integer: Section.batches.rawValue), with: .automatic)
        tableView.reloadSections(IndexSet(integer: Section.controls.rawValue), with: .none)
        updateNavBarButtons()
    }

    private func copyBatch(at index: Int) {
        UIPasteboard.general.string = Self.batches[index].prettyJson
        showToast("Batch JSON copied")
    }

    // MARK: - OTLP Validation

    func validateOtlpStructure() {
        guard !Self.fullJsonLogs.isEmpty else {
            showValidationResult(title: "No Data", message: "No OTLP data to validate.")
            return
        }
        var results: [String] = []
        var totalPassed = 0, totalFailed = 0
        for (i, json) in Self.fullJsonLogs.enumerated() {
            let v = validateSingleExport(json, exportIndex: i + 1)
            results.append(v.report); totalPassed += v.passed; totalFailed += v.failed
        }
        let summary = "Exports: \(Self.fullJsonLogs.count) | ✅ \(totalPassed) | ❌ \(totalFailed)\n\n"
            + results.joined(separator: "\n\n")
        showValidationResult(
            title: totalFailed == 0 ? "✅ All Passed" : "⚠️ Some Failed",
            message: summary
        )
    }

    private struct ValidationResult { let report: String; let passed: Int; let failed: Int }

    private func validateSingleExport(_ jsonString: String, exportIndex: Int) -> ValidationResult {
        var checks: [(name: String, passed: Bool, detail: String)] = []
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ValidationResult(report: "Export #\(exportIndex): ❌ Invalid JSON", passed: 0, failed: 1)
        }
        checks.append(("Valid JSON", true, ""))
        guard let resourceSpans = json["resource_spans"] as? [[String: Any]] else {
            checks.append(("Has resource_spans", false, "Missing"))
            return buildReport(exportIndex: exportIndex, checks: checks)
        }
        checks.append(("Has resource_spans", true, "\(resourceSpans.count)"))
        for (rIdx, rs) in resourceSpans.enumerated() {
            if let r = rs["resource"] as? [String: Any], r["attributes"] is [[String: Any]] {
                checks.append(("Resource[\(rIdx)] attributes", true, ""))
            } else { checks.append(("Resource[\(rIdx)] attributes", false, "Missing")) }
            guard let scopeSpans = rs["scope_spans"] as? [[String: Any]] else {
                checks.append(("Resource[\(rIdx)] scope_spans", false, "Missing")); continue
            }
            checks.append(("Resource[\(rIdx)] scope_spans", true, "\(scopeSpans.count)"))
            for (sIdx, ss) in scopeSpans.enumerated() {
                if let scope = ss["scope"] as? [String: Any], scope["name"] is String {
                    checks.append(("Scope[\(rIdx)][\(sIdx)] name", true, ""))
                } else { checks.append(("Scope[\(rIdx)][\(sIdx)] name", false, "Missing")) }
                guard let spans = ss["spans"] as? [[String: Any]] else {
                    checks.append(("Scope[\(rIdx)][\(sIdx)] spans", false, "Missing")); continue
                }
                checks.append(("Scope[\(rIdx)][\(sIdx)] spans", true, "\(spans.count)"))
                for (spIdx, span) in spans.enumerated() {
                    checks.append(contentsOf: validateSpan(span, path: "Span[\(rIdx)][\(sIdx)][\(spIdx)]"))
                }
            }
        }
        return buildReport(exportIndex: exportIndex, checks: checks)
    }

    private func validateSpan(_ span: [String: Any], path: String) -> [(name: String, passed: Bool, detail: String)] {
        var c: [(name: String, passed: Bool, detail: String)] = []
        if let v = span["trace_id"] as? String { let r = validateBase64(v, bytes: 16); c.append(("\(path) trace_id", r.0, r.1)) }
        else { c.append(("\(path) trace_id", false, "Missing")) }
        if let v = span["span_id"] as? String { let r = validateBase64(v, bytes: 8); c.append(("\(path) span_id", r.0, r.1)) }
        else { c.append(("\(path) span_id", false, "Missing")) }
        if let name = span["name"] as? String, !name.isEmpty { c.append(("\(path) name", true, "'\(name)'")) }
        else { c.append(("\(path) name", false, "Missing")) }
        if let kind = span["kind"] as? String {
            let valid = ["SPAN_KIND_UNSPECIFIED","SPAN_KIND_INTERNAL","SPAN_KIND_SERVER","SPAN_KIND_CLIENT","SPAN_KIND_PRODUCER","SPAN_KIND_CONSUMER"].contains(kind)
            c.append(("\(path) kind", valid, valid ? kind : "Invalid: \(kind)"))
        } else { c.append(("\(path) kind", false, "Missing")) }
        for key in ["start_time_unix_nano", "end_time_unix_nano"] {
            if let t = span[key] as? String { c.append(("\(path) \(key)", UInt64(t) != nil, "")) }
            else { c.append(("\(path) \(key)", false, "Missing")) }
        }
        if let status = span["status"] as? [String: Any], let code = status["code"] as? String {
            let valid = ["STATUS_CODE_UNSET","STATUS_CODE_OK","STATUS_CODE_ERROR"].contains(code)
            c.append(("\(path) status.code", valid, valid ? code : "Invalid: \(code)"))
        } else { c.append(("\(path) status.code", false, "Missing")) }
        return c
    }

    private func validateBase64(_ s: String, bytes: Int) -> (Bool, String) {
        guard let d = Data(base64Encoded: s) else { return (false, "Invalid Base64") }
        return d.count == bytes ? (true, "\(bytes) bytes") : (false, "Expected \(bytes), got \(d.count)")
    }

    private func buildReport(exportIndex: Int, checks: [(name: String, passed: Bool, detail: String)]) -> ValidationResult {
        let p = checks.filter { $0.passed }.count
        let f = checks.filter { !$0.passed }.count
        var r = "--- Export #\(exportIndex) --- Passed: \(p), Failed: \(f)\n"
        for c in checks { r += "\(c.passed ? "✅" : "❌") \(c.name)\(c.detail.isEmpty ? "" : " (\(c.detail))")\n" }
        return ValidationResult(report: r, passed: p, failed: f)
    }

    private func showValidationResult(title: String, message: String) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        let tv = UITextView()
        tv.text = message; tv.isEditable = false
        tv.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        tv.backgroundColor = .clear; tv.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.addSubview(tv); container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: container.topAnchor),
            tv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.heightAnchor.constraint(equalToConstant: 300)
        ])
        alert.view.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: alert.view.topAnchor, constant: 50),
            container.leadingAnchor.constraint(equalTo: alert.view.leadingAnchor, constant: 10),
            container.trailingAnchor.constraint(equalTo: alert.view.trailingAnchor, constant: -10),
            alert.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 400)
        ])
        alert.addAction(UIAlertAction(title: "Copy Report", style: .default) { _ in UIPasteboard.general.string = message })
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
    }

    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { alert.dismiss(animated: true) }
    }
}
