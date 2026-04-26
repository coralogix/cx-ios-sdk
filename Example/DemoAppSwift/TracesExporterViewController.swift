//
//  TracesExporterViewController.swift
//  DemoAppSwift
//
//  Test view for the Traces Exporter (OTLP callback) feature.
//  UI mirrors the Flutter plugin's TracesExporterDemoPage:
//  each received OTLP batch gets its own expandable row.
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

// MARK: - Cell

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

    private let previewLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        l.textColor = .secondaryLabel
        l.numberOfLines = 3
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

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

    private let separator: UIView = {
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

        jsonContainer.addSubview(separator)
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

            separator.topAnchor.constraint(equalTo: jsonContainer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: jsonContainer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: jsonContainer.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            jsonLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
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

        let imageName = batch.isExpanded ? "chevron.up" : "chevron.down"
        expandButton.setImage(UIImage(systemName: imageName), for: .normal)

        previewLabel.isHidden = batch.isExpanded
        jsonContainer.isHidden = !batch.isExpanded
    }

    @objc private func didTapCopy() { onCopy?() }
    @objc private func didTapToggle() { onToggle?() }
}

// MARK: - View Controller

final class TracesExporterViewController: UIViewController {

    // MARK: - Persistent state (survives navigation pop/push)

    private static var isTracesExporterEnabled = false
    private static var batches: [OtlpBatch] = []
    private static var batchCounter = 0
    private static var fullJsonLogs: [String] = []

    // MARK: - UI

    private let tableView: UITableView = {
        let t = UITableView(frame: .zero, style: .plain)
        t.translatesAutoresizingMaskIntoConstraints = false
        t.separatorInset = .zero
        t.rowHeight = UITableView.automaticDimension
        t.estimatedRowHeight = 100
        return t
    }()

    private let headerView = TracesExporterHeaderView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Traces Exporter"
        view.backgroundColor = .systemBackground

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(OtlpBatchCell.self, forCellReuseIdentifier: "batch")

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        headerView.onReinit = { [weak self] in self?.confirmReinitialize() }
        headerView.onTriggerNetwork = { [weak self] in self?.triggerNetworkRequest() }
        headerView.onTriggerCustomSpan = { [weak self] in self?.triggerCustomSpan() }
        headerView.onCopyAll = { [weak self] in self?.copyAll() }
        headerView.onClear = { [weak self] in self?.clearBatches() }
        headerView.onValidate = { [weak self] in self?.validateOtlpStructure() }

        tableView.tableHeaderView = headerView
        updateEmptyState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshHeader()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeaderView()
    }

    private func sizeHeaderView() {
        let targetWidth = tableView.bounds.width
        let size = headerView.systemLayoutSizeFitting(
            CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        if headerView.frame.size != size {
            headerView.frame.size = size
            tableView.tableHeaderView = headerView
        }
    }

    private func refreshHeader() {
        headerView.configure(
            enabled: Self.isTracesExporterEnabled,
            batchCount: Self.batches.count
        )
        sizeHeaderView()
    }

    private func updateEmptyState() {
        if Self.batches.isEmpty {
            let empty = EmptyStateView()
            empty.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 300)
            tableView.backgroundView = empty
        } else {
            tableView.backgroundView = nil
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
                    Self.batches.insert(batch, at: 0)
                    if !jsonString.isEmpty {
                        Self.fullJsonLogs.insert(jsonString, at: 0)
                        if Self.fullJsonLogs.count > 50 { Self.fullJsonLogs.removeLast() }
                    }
                    if Self.batches.count > 50 { Self.batches.removeLast() }

                    self?.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .automatic)
                    self?.updateEmptyState()
                    self?.refreshHeader()
                }
            },
            debug: true
        )

        CoralogixRumManager.shared.reinitialize(with: options)
        Self.isTracesExporterEnabled = true
        refreshHeader()
        showToast("SDK reinitialized with Traces Exporter")
    }

    private func triggerNetworkRequest() {
        guard Self.isTracesExporterEnabled else {
            showToast("Reinitialize SDK with Traces Exporter first")
            return
        }
        NetworkSim.sendSuccesfullRequest()
        showToast("Network request sent")
    }

    private func triggerCustomSpan() {
        guard Self.isTracesExporterEnabled else {
            showToast("Reinitialize SDK with Traces Exporter first")
            return
        }
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

    private func copyAll() {
        guard !Self.fullJsonLogs.isEmpty else { showToast("No OTLP data to copy"); return }
        var out = "=== Traces Exporter Full Log ===\n"
        out += "Total exports: \(Self.fullJsonLogs.count)\n\n"
        for (i, json) in Self.fullJsonLogs.enumerated() {
            out += "=== Export #\(i + 1) ===\n\(json)\n\n"
        }
        UIPasteboard.general.string = out
        showToast("Copied \(Self.fullJsonLogs.count) batch(es) as JSON")
    }

    private func clearBatches() {
        Self.batches.removeAll()
        Self.fullJsonLogs.removeAll()
        Self.batchCounter = 0
        tableView.reloadData()
        updateEmptyState()
        refreshHeader()
    }

    private func copyBatch(at index: Int) {
        let batch = Self.batches[index]
        UIPasteboard.general.string = batch.prettyJson
        showToast("Batch JSON copied")
    }

    // MARK: - OTLP Validation (kept from original)

    private func validateOtlpStructure() {
        guard !Self.fullJsonLogs.isEmpty else {
            showValidationResult(title: "No Data", message: "No OTLP data to validate. Generate some spans first.")
            return
        }
        var results: [String] = []
        var totalPassed = 0, totalFailed = 0
        for (i, json) in Self.fullJsonLogs.enumerated() {
            let v = validateSingleExport(json, exportIndex: i + 1)
            results.append(v.report); totalPassed += v.passed; totalFailed += v.failed
        }
        let summary = """
        === OTLP Validation Summary ===
        Exports validated: \(Self.fullJsonLogs.count)
        Passed: \(totalPassed)  Failed: \(totalFailed)

        \(results.joined(separator: "\n\n"))
        """
        let title = totalFailed == 0 ? "✅ All Validations Passed" : "⚠️ Some Validations Failed"
        showValidationResult(title: title, message: summary)
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
        checks.append(("Has resource_spans", true, "\(resourceSpans.count) resource(s)"))
        for (rIdx, rs) in resourceSpans.enumerated() {
            if let r = rs["resource"] as? [String: Any], r["attributes"] is [[String: Any]] {
                checks.append(("Resource[\(rIdx)] attributes", true, ""))
            } else {
                checks.append(("Resource[\(rIdx)] attributes", false, "Missing"))
            }
            guard let scopeSpans = rs["scope_spans"] as? [[String: Any]] else {
                checks.append(("Resource[\(rIdx)] scope_spans", false, "Missing")); continue
            }
            checks.append(("Resource[\(rIdx)] scope_spans", true, "\(scopeSpans.count)"))
            for (sIdx, ss) in scopeSpans.enumerated() {
                if let scope = ss["scope"] as? [String: Any], scope["name"] is String {
                    checks.append(("Scope[\(rIdx)][\(sIdx)] name", true, ""))
                } else {
                    checks.append(("Scope[\(rIdx)][\(sIdx)] name", false, "Missing"))
                }
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
        if let v = span["trace_id"] as? String { let r = validateBase64(v, expectedBytes: 16); c.append(("\(path) trace_id", r.0, r.1)) }
        else { c.append(("\(path) trace_id", false, "Missing")) }
        if let v = span["span_id"] as? String { let r = validateBase64(v, expectedBytes: 8); c.append(("\(path) span_id", r.0, r.1)) }
        else { c.append(("\(path) span_id", false, "Missing")) }
        if let name = span["name"] as? String, !name.isEmpty { c.append(("\(path) name", true, "'\(name)'")) }
        else { c.append(("\(path) name", false, "Missing")) }
        if let kind = span["kind"] as? String {
            let valid = ["SPAN_KIND_UNSPECIFIED","SPAN_KIND_INTERNAL","SPAN_KIND_SERVER","SPAN_KIND_CLIENT","SPAN_KIND_PRODUCER","SPAN_KIND_CONSUMER"].contains(kind)
            c.append(("\(path) kind", valid, valid ? kind : "Invalid: \(kind)"))
        } else { c.append(("\(path) kind", false, "Missing")) }
        if let t = span["start_time_unix_nano"] as? String { c.append(("\(path) start_time", UInt64(t) != nil, "")) }
        else { c.append(("\(path) start_time", false, "Missing")) }
        if let t = span["end_time_unix_nano"] as? String { c.append(("\(path) end_time", UInt64(t) != nil, "")) }
        else { c.append(("\(path) end_time", false, "Missing")) }
        if let status = span["status"] as? [String: Any], let code = status["code"] as? String {
            let valid = ["STATUS_CODE_UNSET","STATUS_CODE_OK","STATUS_CODE_ERROR"].contains(code)
            c.append(("\(path) status.code", valid, valid ? code : "Invalid: \(code)"))
        } else { c.append(("\(path) status.code", false, "Missing")) }
        return c
    }

    private func validateBase64(_ s: String, expectedBytes: Int) -> (Bool, String) {
        guard let d = Data(base64Encoded: s) else { return (false, "Invalid Base64") }
        return d.count == expectedBytes ? (true, "\(expectedBytes) bytes") : (false, "Expected \(expectedBytes), got \(d.count)")
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

// MARK: - UITableViewDataSource / Delegate

extension TracesExporterViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Self.batches.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "batch", for: indexPath) as! OtlpBatchCell
        cell.configure(with: Self.batches[indexPath.row])
        cell.onCopy = { [weak self] in self?.copyBatch(at: indexPath.row) }
        cell.onToggle = { [weak self, weak tableView] in
            Self.batches[indexPath.row].isExpanded.toggle()
            tableView?.reloadRows(at: [indexPath], with: .automatic)
        }
        return cell
    }
}

// MARK: - Header view

private final class TracesExporterHeaderView: UIView {
    var onReinit: (() -> Void)?
    var onTriggerNetwork: (() -> Void)?
    var onTriggerCustomSpan: (() -> Void)?
    var onCopyAll: (() -> Void)?
    var onClear: (() -> Void)?
    var onValidate: (() -> Void)?

    private let statusLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .headline)
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()

    private let batchCountLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        l.textAlignment = .center
        return l
    }()

    private lazy var reinitButton = makeButton("Reinitialize SDK with Traces Exporter", style: .body, action: #selector(didTapReinit))
    private lazy var networkButton = makeButton("Trigger Network Request", style: .body, action: #selector(didTapNetwork))
    private lazy var customSpanButton = makeButton("Trigger Custom Span", style: .body, action: #selector(didTapCustomSpan))
    private lazy var copyAllButton = makeButton("Copy All JSON", style: .footnote, action: #selector(didTapCopyAll))
    private lazy var clearButton: UIButton = {
        let b = makeButton("Clear", style: .footnote, action: #selector(didTapClear))
        b.setTitleColor(.systemRed, for: .normal)
        return b
    }()
    private lazy var validateButton = makeButton("Validate OTLP", style: .footnote, action: #selector(didTapValidate))

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func makeButton(_ title: String, style: UIFont.TextStyle, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .preferredFont(forTextStyle: style)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private func setupLayout() {
        let bottomRow = UIStackView(arrangedSubviews: [copyAllButton, clearButton, validateButton])
        bottomRow.axis = .horizontal; bottomRow.spacing = 16; bottomRow.distribution = .equalCentering

        let stack = UIStackView(arrangedSubviews: [
            statusLabel, batchCountLabel,
            reinitButton, networkButton, customSpanButton,
            bottomRow
        ])
        stack.axis = .vertical; stack.spacing = 12; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let sep = UIView()
        sep.backgroundColor = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            sep.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 16),
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 0.5),
            sep.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func configure(enabled: Bool, batchCount: Int) {
        if enabled {
            statusLabel.text = "✅ Traces Exporter: ENABLED"
            statusLabel.textColor = .systemGreen
            reinitButton.isEnabled = false
            reinitButton.setTitle("SDK already initialized with Traces Exporter", for: .normal)
        } else {
            statusLabel.text = "⚠️ Traces Exporter: DISABLED"
            statusLabel.textColor = .systemOrange
            reinitButton.isEnabled = true
            reinitButton.setTitle("Reinitialize SDK with Traces Exporter", for: .normal)
        }
        batchCountLabel.text = "Batches received: \(batchCount)"
    }

    @objc private func didTapReinit() { onReinit?() }
    @objc private func didTapNetwork() { onTriggerNetwork?() }
    @objc private func didTapCustomSpan() { onTriggerCustomSpan?() }
    @objc private func didTapCopyAll() { onCopyAll?() }
    @objc private func didTapClear() { onClear?() }
    @objc private func didTapValidate() { onValidate?() }
}

// MARK: - Empty state

private final class EmptyStateView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        let icon = UIImageView(image: UIImage(systemName: "tray"))
        icon.tintColor = UIColor.secondaryLabel.withAlphaComponent(0.4)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "No batches yet"
        title.font = .preferredFont(forTextStyle: .title3)
        title.textColor = .secondaryLabel
        title.textAlignment = .center

        let body = UILabel()
        body.text = "Run a custom spans demo or any SDK instrumentation to produce spans.\nEach OTLP batch delivered via the tracesExporter callback appears here."
        body.font = .preferredFont(forTextStyle: .footnote)
        body.textColor = .tertiaryLabel
        body.textAlignment = .center
        body.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, title, body])
        stack.axis = .vertical; stack.spacing = 12; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 60),
            icon.heightAnchor.constraint(equalToConstant: 60),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}
