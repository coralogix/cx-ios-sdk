//
//  LogSamplingDecouplingViewController.swift
//  DemoAppSwift
//
//  Manual harness for PIPEV2-3365: pick a sessionSampleRate (0/50/100) and an
//  excludeFromSampling set, reinitialize the SDK with that config, then fire
//  events and watch which event_types actually survive the sampling filter
//  via the tracesExporter callback.
//

import UIKit
import Coralogix
import CoralogixInternal

private struct CapturedSpan {
    let eventType: String
    let name: String
    let receivedAt: Date

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: receivedAt)
    }
}

final class LogSamplingDecouplingViewController: UIViewController {

    // MARK: - Persistent state

    private static var currentSampleRate: Int = 0
    private static var currentExclude: Set<ExcludableInstrumentation> = [.logs]
    private static var isApplied = false
    private static var captured: [CapturedSpan] = []

    private static let allExcludable: [ExcludableInstrumentation] =
        [.logs, .errors, .network, .userInteractions, .mobileVitals, .customSpan, .customMeasurement]

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let sampleRateSegmented = UISegmentedControl(items: ["0%", "50%", "100%"])
    private let statusLabel = UILabel()
    private let appliedConfigLabel = UILabel()
    private var excludeToggles: [ExcludableInstrumentation: UISwitch] = [:]

    private lazy var applyButton: UIButton = makeButton("Apply (reinit SDK)",
                                                        icon: "arrow.clockwise.circle",
                                                        action: #selector(didTapApply))
    private lazy var sendLogButton: UIButton = makeButton("Send Log",
                                                          icon: "text.bubble",
                                                          action: #selector(didTapSendLog))
    private lazy var sendErrorButton: UIButton = makeButton("Send Error",
                                                            icon: "exclamationmark.triangle",
                                                            action: #selector(didTapSendError))
    private lazy var sendNetworkButton: UIButton = makeButton("Send Network",
                                                              icon: "network",
                                                              action: #selector(didTapSendNetwork))
    private lazy var sendCustomSpanButton: UIButton = makeButton("Send Custom Span",
                                                                  icon: "point.3.connected.trianglepath.dotted",
                                                                  action: #selector(didTapSendCustomSpan))
    private lazy var clearButton: UIButton = makeButton("Clear captured",
                                                        icon: "trash",
                                                        action: #selector(didTapClear))

    private let capturedTable = UITableView(frame: .zero, style: .plain)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Log Sampling Decoupling"
        view.backgroundColor = .systemBackground

        setupLayout()
        configureFromState()
        capturedTable.dataSource = self
        capturedTable.delegate = self
        capturedTable.register(UITableViewCell.self, forCellReuseIdentifier: "captured")
        updateAppliedConfigLabel()
        updateButtonsEnabled()
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.alignment = .fill

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])

        contentStack.addArrangedSubview(makeSectionHeader("sessionSampleRate"))
        sampleRateSegmented.addTarget(self, action: #selector(sampleRateChanged), for: .valueChanged)
        contentStack.addArrangedSubview(sampleRateSegmented)

        contentStack.addArrangedSubview(makeSectionHeader("excludeFromSampling"))
        for excludable in Self.allExcludable {
            let row = makeExcludeRow(excludable)
            contentStack.addArrangedSubview(row)
        }

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.numberOfLines = 0
        contentStack.addArrangedSubview(statusLabel)
        contentStack.addArrangedSubview(applyButton)

        contentStack.addArrangedSubview(makeSectionHeader("Applied config"))
        appliedConfigLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        appliedConfigLabel.textColor = .secondaryLabel
        appliedConfigLabel.numberOfLines = 0
        contentStack.addArrangedSubview(appliedConfigLabel)

        contentStack.addArrangedSubview(makeSectionHeader("Trigger events"))
        let triggers = UIStackView(arrangedSubviews: [sendLogButton, sendErrorButton])
        triggers.axis = .horizontal
        triggers.spacing = 8
        triggers.distribution = .fillEqually
        let triggers2 = UIStackView(arrangedSubviews: [sendNetworkButton, sendCustomSpanButton])
        triggers2.axis = .horizontal
        triggers2.spacing = 8
        triggers2.distribution = .fillEqually
        contentStack.addArrangedSubview(triggers)
        contentStack.addArrangedSubview(triggers2)

        contentStack.addArrangedSubview(makeSectionHeader("Captured (tracesExporter)"))
        contentStack.addArrangedSubview(clearButton)

        capturedTable.translatesAutoresizingMaskIntoConstraints = false
        capturedTable.layer.cornerRadius = 10
        capturedTable.layer.borderWidth = 0.5
        capturedTable.layer.borderColor = UIColor.separator.cgColor
        capturedTable.heightAnchor.constraint(equalToConstant: 240).isActive = true
        contentStack.addArrangedSubview(capturedTable)
    }

    private func configureFromState() {
        switch Self.currentSampleRate {
        case 0:   sampleRateSegmented.selectedSegmentIndex = 0
        case 50:  sampleRateSegmented.selectedSegmentIndex = 1
        default:  sampleRateSegmented.selectedSegmentIndex = 2
        }
        for (excludable, toggle) in excludeToggles {
            toggle.isOn = Self.currentExclude.contains(excludable)
        }
        updateStatusLabel()
    }

    // MARK: - Actions

    @objc private func sampleRateChanged() {
        Self.currentSampleRate = [0, 50, 100][sampleRateSegmented.selectedSegmentIndex]
        updateStatusLabel()
    }

    @objc private func excludeToggleChanged(_ toggle: UISwitch) {
        guard let excludable = Self.allExcludable.first(where: { excludeToggles[$0] === toggle }) else { return }
        if toggle.isOn {
            Self.currentExclude.insert(excludable)
        } else {
            Self.currentExclude.remove(excludable)
        }
        updateStatusLabel()
    }

    @objc private func didTapApply() {
        let rate = Self.currentSampleRate
        let exclude = Self.currentExclude
        if rate == 0 && exclude.isEmpty {
            showToast("sampleRate=0 + exclude=[] would skip init (legacy contract). Pick a rate or an exclude.")
            return
        }

        CoralogixRumManager.shared.sdk.shutdown()
        let options = CoralogixExporterOptions(
            coralogixDomain: .EU2,
            userContext: UserContext(userId: "sampling-test",
                                     userName: "Sampling Tester",
                                     userEmail: "sampling@example.com",
                                     userMetadata: ["test": "logSamplingDecoupling"]),
            environment: "PROD",
            application: "DemoApp-iOS-LogSamplingDecoupling",
            version: "1",
            publicKey: Envs.PUBLIC_KEY.rawValue,
            sessionSampleRate: rate,
            excludeFromSampling: exclude,
            instrumentations: [.mobileVitals: true, .custom: true, .errors: true,
                               .userActions: true, .network: true, .anr: true, .lifeCycle: true],
            collectIPData: true,
            traceParentInHeader: ["enable": true],
            tracesExporter: { [weak self] data in
                let now = Date()
                var rows: [CapturedSpan] = []
                for resourceSpan in data.tracesData.resourceSpans {
                    for scopeSpan in resourceSpan.scopeSpans {
                        for span in scopeSpan.spans {
                            rows.append(CapturedSpan(
                                eventType: Self.eventType(in: span) ?? "(no event_type)",
                                name: span.name,
                                receivedAt: now
                            ))
                        }
                    }
                }
                guard !rows.isEmpty else { return }
                DispatchQueue.main.async {
                    Self.captured.insert(contentsOf: rows.reversed(), at: 0)
                    self?.capturedTable.reloadData()
                }
            },
            debug: true
        )
        CoralogixRumManager.shared.reinitialize(with: options)
        Self.isApplied = true
        updateAppliedConfigLabel()
        updateButtonsEnabled()
        showToast("SDK reinitialized — rate=\(rate), exclude=\(formatExclude(exclude))")
    }

    @objc private func didTapSendLog() {
        CoralogixRumManager.shared.sdk.log(severity: .info,
                                           message: "Sampling demo log",
                                           data: ["source": "LogSamplingDecouplingVC"])
        showToast("log() called")
    }

    @objc private func didTapSendError() {
        CoralogixRumManager.shared.sdk.reportError(message: "Sampling demo error", data: nil)
        showToast("reportError() called")
    }

    @objc private func didTapSendNetwork() {
        NetworkSim.sendSuccesfullRequest()
        showToast("Network request sent")
    }

    @objc private func didTapSendCustomSpan() {
        let rum = CoralogixRumManager.shared.sdk
        guard rum.isInitialized else { showToast("SDK not initialized"); return }
        guard let tracer = rum.getCustomTracer() else { showToast("Failed to get custom tracer"); return }
        guard let global = tracer.startGlobalSpan(name: "sampling-demo.global",
                                                   labels: ["source": "LogSamplingDecouplingVC"]) else {
            showToast("startGlobalSpan returned nil")
            return
        }
        let child = global.startCustomSpan(name: "sampling-demo.child")
        child.endSpan()
        global.endSpan()
        showToast("Custom span emitted")
    }

    @objc private func didTapClear() {
        Self.captured.removeAll()
        capturedTable.reloadData()
    }

    // MARK: - Helpers

    private static func eventType(in span: OtlpSpan) -> String? {
        guard let kv = span.attributes.first(where: { $0.key == CoralogixInternal.Keys.eventType.rawValue }) else { return nil }
        if case .stringValue(let value) = kv.value { return value }
        return nil
    }

    private func updateStatusLabel() {
        let rate = Self.currentSampleRate
        let exclude = Self.currentExclude
        if rate == 0 && exclude.isEmpty {
            statusLabel.text = "⚠️ rate=0 + exclude=[] would short-circuit init (legacy contract). Apply will refuse this combination."
            statusLabel.textColor = .systemOrange
        } else if rate == 100 {
            statusLabel.text = "ℹ️ Sampled in: every event passes regardless of excludeFromSampling."
            statusLabel.textColor = .secondaryLabel
        } else if rate == 0 {
            statusLabel.text = "ℹ️ Sampled out (rate=0): only event_types in excludeFromSampling will be exported."
            statusLabel.textColor = .secondaryLabel
        } else {
            statusLabel.text = "ℹ️ ~\(rate)% of fresh sessions roll sampled-in. Reinit (or relaunch) to roll a new session."
            statusLabel.textColor = .secondaryLabel
        }
    }

    private func updateAppliedConfigLabel() {
        if Self.isApplied {
            appliedConfigLabel.text =
                "rate=\(Self.currentSampleRate)\n" +
                "exclude=\(formatExclude(Self.currentExclude))\n" +
                "isInitialized=\(CoralogixRumManager.shared.sdk.isInitialized)"
        } else {
            appliedConfigLabel.text = "(not applied — tap Apply to reinit the SDK)"
        }
    }

    private func updateButtonsEnabled() {
        let on = Self.isApplied
        for btn in [sendLogButton, sendErrorButton, sendNetworkButton, sendCustomSpanButton] {
            btn.isEnabled = on
            btn.alpha = on ? 1 : 0.4
        }
    }

    private func formatExclude(_ set: Set<ExcludableInstrumentation>) -> String {
        if set.isEmpty { return "[]" }
        return "[" + set.map { ".\($0.rawValue)" }.sorted().joined(separator: ", ") + "]"
    }

    // MARK: - View builders

    private func makeSectionHeader(_ title: String) -> UILabel {
        let l = UILabel()
        l.text = title
        l.font = .preferredFont(forTextStyle: .headline)
        return l
    }

    private func makeExcludeRow(_ excludable: ExcludableInstrumentation) -> UIView {
        let label = UILabel()
        label.text = ".\(excludable.rawValue)"
        label.font = .preferredFont(forTextStyle: .body)

        let toggle = UISwitch()
        toggle.isOn = Self.currentExclude.contains(excludable)
        toggle.addTarget(self, action: #selector(excludeToggleChanged(_:)), for: .valueChanged)
        excludeToggles[excludable] = toggle

        let row = UIStackView(arrangedSubviews: [label, UIView(), toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        return row
    }

    private func makeButton(_ title: String, icon: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(" " + title, for: .normal)
        btn.setImage(UIImage(systemName: icon), for: .normal)
        btn.titleLabel?.font = .preferredFont(forTextStyle: .body)
        btn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        btn.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        btn.layer.cornerRadius = 10
        btn.tintColor = .systemBlue
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { alert.dismiss(animated: true) }
    }
}

// MARK: - Captured table

extension LogSamplingDecouplingViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(Self.captured.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "captured", for: indexPath)
        cell.selectionStyle = .none
        var config = UIListContentConfiguration.subtitleCell()
        if Self.captured.isEmpty {
            config.text = "(no spans yet — apply a config and trigger events)"
            config.textProperties.color = .secondaryLabel
            config.textProperties.font = .preferredFont(forTextStyle: .footnote)
        } else {
            let row = Self.captured[indexPath.row]
            config.text = row.eventType
            config.secondaryText = "\(row.timeString)  ·  \(row.name)"
            config.textProperties.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            config.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption2)
            config.secondaryTextProperties.color = .secondaryLabel
        }
        cell.contentConfiguration = config
        return cell
    }
}
