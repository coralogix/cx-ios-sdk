//
//  LogSamplingDecouplingViewController.swift
//  DemoAppSwift
//
//  UIKit presenter on top of LogSamplingDemoModel — pick a sessionSampleRate +
//  excludeFromSampling set, reinitialize the SDK, fire events, and watch which
//  event_types survive the sampling filter via the tracesExporter callback.
//

import UIKit
import Combine
import Coralogix
import CoralogixInternal

final class LogSamplingDecouplingViewController: UIViewController {

    private let model = LogSamplingDemoModel.shared
    private var cancellables = Set<AnyCancellable>()

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
    private lazy var sendCustomMeasurementButton: UIButton = makeButton("Send Custom Measurement",
                                                                         icon: "ruler",
                                                                         action: #selector(didTapSendCustomMeasurement))
    private lazy var clearButton: UIButton = makeButton("Clear captured",
                                                        icon: "trash",
                                                        action: #selector(didTapClear))

    private let capturedTable = UITableView(frame: .zero, style: .plain)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Log Sampling Decoupling"
        view.backgroundColor = .systemBackground

        setupLayout()
        capturedTable.dataSource = self
        capturedTable.delegate = self
        capturedTable.register(UITableViewCell.self, forCellReuseIdentifier: "captured")

        configureFromModel()
        refreshFromModel()

        // The model emits objectWillChange before each @Published mutation; sink on the
        // main queue and re-render the parts of the UI that depend on model state.
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refreshFromModel() }
            .store(in: &cancellables)
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
        for excludable in LogSamplingDemoModel.allExcludable {
            contentStack.addArrangedSubview(makeExcludeRow(excludable))
        }

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.numberOfLines = 0
        contentStack.addArrangedSubview(statusLabel)
        contentStack.addArrangedSubview(applyButton)

        let applyNote = UILabel()
        applyNote.text = "Apply rebuilds the SDK on EU2 with all instrumentations on; overrides the initial CoralogixRumManager config."
        applyNote.font = .preferredFont(forTextStyle: .caption2)
        applyNote.textColor = .tertiaryLabel
        applyNote.numberOfLines = 0
        contentStack.addArrangedSubview(applyNote)

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
        contentStack.addArrangedSubview(sendCustomMeasurementButton)

        contentStack.addArrangedSubview(makeSectionHeader("Captured (tracesExporter)"))
        contentStack.addArrangedSubview(clearButton)

        capturedTable.translatesAutoresizingMaskIntoConstraints = false
        capturedTable.layer.cornerRadius = 10
        capturedTable.layer.borderWidth = 0.5
        capturedTable.layer.borderColor = UIColor.separator.cgColor
        capturedTable.heightAnchor.constraint(equalToConstant: 240).isActive = true
        contentStack.addArrangedSubview(capturedTable)
    }

    private func configureFromModel() {
        switch model.sampleRate {
        case 0:   sampleRateSegmented.selectedSegmentIndex = 0
        case 50:  sampleRateSegmented.selectedSegmentIndex = 1
        default:  sampleRateSegmented.selectedSegmentIndex = 2
        }
        for (excludable, toggle) in excludeToggles {
            toggle.isOn = model.exclude.contains(excludable)
        }
    }

    private func refreshFromModel() {
        capturedTable.reloadData()
        updateStatusLabel()
        updateAppliedConfigLabel()
        updateButtonsEnabled()
    }

    // MARK: - Actions

    @objc private func sampleRateChanged() {
        model.sampleRate = [0, 50, 100][sampleRateSegmented.selectedSegmentIndex]
    }

    @objc private func excludeToggleChanged(_ toggle: UISwitch) {
        guard let excludable = LogSamplingDemoModel.allExcludable.first(where: { excludeToggles[$0] === toggle }) else { return }
        if toggle.isOn {
            model.exclude.insert(excludable)
        } else {
            model.exclude.remove(excludable)
        }
    }

    @objc private func didTapApply() { showToast(model.apply()) }
    @objc private func didTapSendLog() { showToast(model.triggerLog()) }
    @objc private func didTapSendError() { showToast(model.triggerError()) }
    @objc private func didTapSendNetwork() { showToast(model.triggerNetwork()) }
    @objc private func didTapSendCustomSpan() { showToast(model.triggerCustomSpan()) }
    @objc private func didTapSendCustomMeasurement() { showToast(model.triggerCustomMeasurement()) }
    @objc private func didTapClear() { model.clearCaptured() }

    // MARK: - View state derived from model

    private func updateStatusLabel() {
        let rate = model.sampleRate
        let empty = model.exclude.isEmpty
        if rate == 0 && empty {
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
        if model.isApplied {
            appliedConfigLabel.text =
                "rate=\(model.sampleRate)\n" +
                "exclude=\(model.formattedExclude)\n" +
                "isInitialized=\(CoralogixRumManager.shared.sdk.isInitialized)"
        } else {
            appliedConfigLabel.text = "(not applied — tap Apply to reinit the SDK)"
        }
    }

    private func updateButtonsEnabled() {
        let on = model.isApplied
        for btn in [sendLogButton, sendErrorButton, sendNetworkButton, sendCustomSpanButton, sendCustomMeasurementButton] {
            btn.isEnabled = on
            btn.alpha = on ? 1 : 0.4
        }
    }

    // MARK: - View builders

    private func makeSectionHeader(_ title: String) -> UIView {
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
        toggle.isOn = model.exclude.contains(excludable)
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
        // contentEdgeInsets is deprecated in iOS 15 (replaced by UIButton.Configuration),
        // but the demo app's deployment target is iOS 13 so the modern API isn't available.
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
        max(model.captured.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "captured", for: indexPath)
        cell.selectionStyle = .none
        var config = UIListContentConfiguration.subtitleCell()
        if model.captured.isEmpty {
            config.text = "(no spans yet — apply a config and trigger events)"
            config.textProperties.color = .secondaryLabel
            config.textProperties.font = .preferredFont(forTextStyle: .footnote)
        } else {
            let row = model.captured[indexPath.row]
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
