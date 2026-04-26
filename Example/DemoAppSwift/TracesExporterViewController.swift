//
//  TracesExporterViewController.swift
//  DemoAppSwift
//
//  Each individual OtlpSpan received via the tracesExporter callback
//  gets its own row in a table. Controls are fixed above the table
//  and do not scroll with it.
//

import UIKit
import Coralogix

// MARK: - Model

private struct SpanRow {
    let name: String
    let spanId: String
    let traceId: String
    let parentSpanId: String?
    let kind: OtlpSpanKind
    let statusCode: String
    let receivedAt: Date
    let otlpSpan: OtlpSpan
    var isExpanded: Bool = false

    var prettyJson: String {
        guard let data = try? JSONEncoder().encode(otlpSpan),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else { return spanId }
        return str
    }

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: receivedAt)
    }

    var kindShort: String {
        switch kind {
        case .client:   return "CLIENT"
        case .server:   return "SERVER"
        case .internal: return "INTERNAL"
        case .producer: return "PRODUCER"
        case .consumer: return "CONSUMER"
        case .unspecified: return "SPAN"
        }
    }
}

// MARK: - Span Cell

private final class SpanRowCell: UITableViewCell {
    var onCopy: (() -> Void)?
    var onToggle: (() -> Void)?

    private let kindBadge: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 9, weight: .bold)
        l.textAlignment = .center
        l.textColor = .white
        l.backgroundColor = .systemIndigo
        l.layer.cornerRadius = 6
        l.clipsToBounds = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .subheadline)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let timeLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .caption2)
        l.textColor = .secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let spanIdLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        l.textColor = .secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let traceIdLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        l.textColor = .tertiaryLabel
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
        let topRow = UIStackView(arrangedSubviews: [kindBadge, nameLabel, timeLabel, copyButton, expandButton])
        topRow.axis = .horizontal
        topRow.spacing = 8
        topRow.alignment = .center
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let idStack = UIStackView(arrangedSubviews: [spanIdLabel, traceIdLabel])
        idStack.axis = .vertical
        idStack.spacing = 1

        // jsonContainer internal layout
        jsonContainer.addSubview(jsonSeparator)
        jsonContainer.addSubview(jsonLabel)
        NSLayoutConstraint.activate([
            jsonSeparator.topAnchor.constraint(equalTo: jsonContainer.topAnchor),
            jsonSeparator.leadingAnchor.constraint(equalTo: jsonContainer.leadingAnchor),
            jsonSeparator.trailingAnchor.constraint(equalTo: jsonContainer.trailingAnchor),
            jsonSeparator.heightAnchor.constraint(equalToConstant: 0.5),
            jsonLabel.topAnchor.constraint(equalTo: jsonSeparator.bottomAnchor, constant: 10),
            jsonLabel.leadingAnchor.constraint(equalTo: jsonContainer.leadingAnchor, constant: 16),
            jsonLabel.trailingAnchor.constraint(equalTo: jsonContainer.trailingAnchor, constant: -16),
            jsonLabel.bottomAnchor.constraint(equalTo: jsonContainer.bottomAnchor, constant: -10),
        ])

        // Outer vertical stack — hidden arranged subviews collapse automatically
        let outerStack = UIStackView(arrangedSubviews: [topRow, idStack, jsonContainer])
        outerStack.axis = .vertical
        outerStack.spacing = 4
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(outerStack)
        NSLayoutConstraint.activate([
            kindBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
            kindBadge.heightAnchor.constraint(equalToConstant: 18),
            outerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            outerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            outerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            outerStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
        // jsonContainer needs full-width bleed so override leading/trailing
        jsonContainer.translatesAutoresizingMaskIntoConstraints = false
    }

    func configure(with row: SpanRow) {
        kindBadge.text = "  \(row.kindShort)  "
        kindBadge.backgroundColor = row.parentSpanId != nil ? .systemGreen : .systemIndigo
        nameLabel.text = row.name
        timeLabel.text = row.timeString
        spanIdLabel.text = "spanId: \(row.spanId)"
        let tracePrefix = row.traceId.count > 16 ? String(row.traceId.prefix(16)) + "…" : row.traceId
        traceIdLabel.text = row.parentSpanId != nil
            ? "traceId: \(tracePrefix)  ↑ \(row.parentSpanId!)"
            : "traceId: \(tracePrefix)"

        expandButton.setImage(UIImage(systemName: row.isExpanded ? "chevron.up" : "chevron.down"), for: .normal)
        jsonLabel.text = row.prettyJson
        jsonContainer.isHidden = !row.isExpanded
    }

    @objc private func didTapCopy() { onCopy?() }
    @objc private func didTapToggle() { onToggle?() }
}

// MARK: - View Controller

final class TracesExporterViewController: UIViewController {

    // MARK: - Persistent state

    private static var isTracesExporterEnabled = false
    private static var spans: [SpanRow] = []
    private static var fullJsonLogs: [String] = []

    // MARK: - Fixed controls (do not scroll)

    private let statusLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .footnote)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var reinitButton: UIButton = makeControlButton(
        "Reinitialize SDK with Traces Exporter",
        icon: "arrow.clockwise.circle",
        action: #selector(didTapReinit)
    )
    private lazy var networkButton: UIButton = makeControlButton(
        "Trigger Network Request",
        icon: "network",
        action: #selector(didTapNetwork)
    )
    private lazy var customSpanButton: UIButton = makeControlButton(
        "Trigger Custom Span",
        icon: "point.3.connected.trianglepath.dotted",
        action: #selector(didTapCustomSpan)
    )

    private let controlsDivider: UIView = {
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Span table

    private let tableView: UITableView = {
        let t = UITableView(frame: .zero, style: .plain)
        t.translatesAutoresizingMaskIntoConstraints = false
        t.rowHeight = UITableView.automaticDimension
        t.estimatedRowHeight = 72
        t.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        return t
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Traces Exporter"
        view.backgroundColor = .systemBackground
        navigationController?.navigationBar.prefersLargeTitles = false

        setupLayout()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SpanRowCell.self, forCellReuseIdentifier: "span")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "empty")

        updateControls()
        updateNavBarButtons()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateControls()
        updateNavBarButtons()
    }

    private func setupLayout() {
        let buttonRow = UIStackView(arrangedSubviews: [reinitButton, networkButton, customSpanButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 0
        buttonRow.distribution = .fillEqually
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let controlsStack = UIStackView(arrangedSubviews: [statusLabel, buttonRow])
        controlsStack.axis = .vertical
        controlsStack.spacing = 6
        controlsStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(controlsStack)
        view.addSubview(controlsDivider)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            controlsStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            controlsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            controlsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            controlsDivider.topAnchor.constraint(equalTo: controlsStack.bottomAnchor, constant: 10),
            controlsDivider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsDivider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsDivider.heightAnchor.constraint(equalToConstant: 0.5),

            tableView.topAnchor.constraint(equalTo: controlsDivider.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeControlButton(_ title: String, icon: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false

        let imageView = UIImageView(image: UIImage(systemName: icon))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [imageView, label])
        stack.axis = .vertical
        stack.spacing = 3
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        b.addSubview(stack)
        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: 22),
            imageView.widthAnchor.constraint(equalToConstant: 22),
            stack.topAnchor.constraint(equalTo: b.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -4),
        ])

        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    // MARK: - State updates

    private func updateControls() {
        if Self.isTracesExporterEnabled {
            statusLabel.text = "✅ Traces Exporter enabled — \(Self.spans.count) span(s) received"
            statusLabel.textColor = .secondaryLabel
            reinitButton.isEnabled = false
            reinitButton.alpha = 0.4
        } else {
            statusLabel.text = "⚠️ Reinitialize SDK to enable the Traces Exporter"
            statusLabel.textColor = .systemOrange
            reinitButton.isEnabled = true
            reinitButton.alpha = 1
        }
        networkButton.isEnabled = Self.isTracesExporterEnabled
        customSpanButton.isEnabled = Self.isTracesExporterEnabled
        networkButton.alpha = Self.isTracesExporterEnabled ? 1 : 0.4
        customSpanButton.alpha = Self.isTracesExporterEnabled ? 1 : 0.4
    }

    private func updateNavBarButtons() {
        guard !Self.spans.isEmpty else {
            navigationItem.rightBarButtonItems = nil
            return
        }
        let copyBtn = UIBarButtonItem(image: UIImage(systemName: "doc.on.doc"), style: .plain,
                                      target: self, action: #selector(copyAll))
        let clearBtn = UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain,
                                       target: self, action: #selector(clearSpans))
        clearBtn.tintColor = .systemRed
        navigationItem.rightBarButtonItems = [clearBtn, copyBtn]
    }

    // MARK: - Actions

    @objc private func didTapReinit() {
        let alert = UIAlertController(
            title: "Reinitialize SDK",
            message: "Shuts down the current SDK and reinitializes it with the tracesExporter callback enabled.",
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
                let now = Date()
                // Flatten all spans from this batch into individual rows
                var newRows: [SpanRow] = []
                for resourceSpan in data.tracesData.resourceSpans {
                    for scopeSpan in resourceSpan.scopeSpans {
                        for span in scopeSpan.spans {
                            newRows.append(SpanRow(
                                name: span.name,
                                spanId: span.spanId,
                                traceId: span.traceId,
                                parentSpanId: span.parentSpanId,
                                kind: span.kind,
                                statusCode: span.status.code.rawValue,
                                receivedAt: now,
                                otlpSpan: span
                            ))
                        }
                    }
                }
                if let json = data.jsonString {
                    DispatchQueue.main.async { Self.fullJsonLogs.insert(json, at: 0) }
                }
                guard !newRows.isEmpty else { return }
                DispatchQueue.main.async { [weak self] in
                    let wasEmpty = Self.spans.isEmpty
                    // Insert newest at top
                    Self.spans.insert(contentsOf: newRows.reversed(), at: 0)
                    if wasEmpty {
                        self?.tableView.reloadData()
                    } else {
                        let paths = (0..<newRows.count).map { IndexPath(row: $0, section: 0) }
                        self?.tableView.insertRows(at: paths, with: .automatic)
                    }
                    self?.updateControls()
                    self?.updateNavBarButtons()
                }
            },
            debug: true
        )

        CoralogixRumManager.shared.reinitialize(with: options)
        Self.isTracesExporterEnabled = true
        updateControls()
        showToast("SDK reinitialized with Traces Exporter")
    }

    @objc private func didTapNetwork() {
        guard Self.isTracesExporterEnabled else { return }
        NetworkSim.sendSuccesfullRequest()
        showToast("Network request sent")
    }

    @objc private func didTapCustomSpan() {
        guard Self.isTracesExporterEnabled else { return }
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
        guard !Self.fullJsonLogs.isEmpty else { showToast("No data to copy"); return }
        var out = "=== Traces Exporter Full Log ===\nTotal exports: \(Self.fullJsonLogs.count)\n\n"
        for (i, json) in Self.fullJsonLogs.enumerated() { out += "=== Export #\(i + 1) ===\n\(json)\n\n" }
        UIPasteboard.general.string = out
        showToast("Copied \(Self.fullJsonLogs.count) export(s)")
    }

    @objc private func clearSpans() {
        Self.spans.removeAll()
        Self.fullJsonLogs.removeAll()
        tableView.reloadData()
        updateControls()
        updateNavBarButtons()
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
        max(Self.spans.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if Self.spans.isEmpty {
            let cell = tableView.dequeueReusableCell(withIdentifier: "empty", for: indexPath)
            cell.selectionStyle = .none
            var config = UIListContentConfiguration.cell()
            config.text = "No spans yet — trigger a network request or custom span."
            config.image = UIImage(systemName: "tray")
            config.textProperties.color = .secondaryLabel
            config.textProperties.numberOfLines = 0
            config.imageProperties.tintColor = .tertiaryLabel
            cell.contentConfiguration = config
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "span", for: indexPath) as! SpanRowCell
        let row = indexPath.row
        cell.configure(with: Self.spans[row])
        cell.onCopy = { [weak self] in
            UIPasteboard.general.string = Self.spans[row].prettyJson
            self?.showToast("Span JSON copied")
        }
        cell.onToggle = { [weak self] in
            Self.spans[row].isExpanded.toggle()
            self?.tableView.reloadRows(at: [indexPath], with: .automatic)
        }
        return cell
    }
}
