//
//  TimeMeasurementViewController.swift
//  DemoAppSwift
//
//  UIKit presenter on top of TimeMeasurementDemoModel — exercise startTimeMeasure /
//  endTimeMeasure manually (name + labels TextFields, Start / End buttons) or via
//  the Quick presets, then watch the resulting custom-measurement spans land in the
//  Captured list via the model's tracesExporter callback.
//

import UIKit
import Combine
import Coralogix
import CoralogixInternal

final class TimeMeasurementViewController: UIViewController {

    private let model = TimeMeasurementDemoModel.shared
    private var cancellables = Set<AnyCancellable>()

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let appliedConfigLabel = UILabel()
    private let nameField = UITextField()
    private let labelsField = UITextField()
    private let inFlightLabel = UILabel()

    private lazy var applyButton = makeButton("Apply (reinit SDK)",
                                              icon: "arrow.clockwise.circle",
                                              action: #selector(didTapApply))
    private lazy var startButton = makeButton("Start", icon: "play.circle", action: #selector(didTapStart))
    private lazy var endButton = makeButton("End", icon: "stop.circle", action: #selector(didTapEnd))
    private lazy var quick100Button = makeButton("Run 100ms", icon: "timer", action: #selector(didTapQuick100))
    private lazy var quick500Button = makeButton("Run 500ms", icon: "timer", action: #selector(didTapQuick500))
    private lazy var quick1sButton = makeButton("Run 1s", icon: "timer", action: #selector(didTapQuick1s))
    private lazy var clearButton = makeButton("Clear captured", icon: "trash", action: #selector(didTapClear))

    private let capturedTable = UITableView(frame: .zero, style: .plain)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Custom Time Measurement"
        view.backgroundColor = .systemBackground

        setupLayout()
        capturedTable.dataSource = self
        capturedTable.delegate = self
        capturedTable.register(UITableViewCell.self, forCellReuseIdentifier: "captured")

        nameField.text = model.timerName
        labelsField.text = model.labelsText
        refreshFromModel()

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

        contentStack.addArrangedSubview(makeSectionHeader("Status"))
        contentStack.addArrangedSubview(applyButton)

        let applyNote = UILabel()
        applyNote.text = "Apply rebuilds the SDK on EU2 with sampleRate=100 and a tracesExporter that captures custom-measurement spans below."
        applyNote.font = .preferredFont(forTextStyle: .caption2)
        applyNote.textColor = .tertiaryLabel
        applyNote.numberOfLines = 0
        contentStack.addArrangedSubview(applyNote)

        appliedConfigLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        appliedConfigLabel.textColor = .secondaryLabel
        appliedConfigLabel.numberOfLines = 0
        contentStack.addArrangedSubview(appliedConfigLabel)

        contentStack.addArrangedSubview(makeSectionHeader("Manual"))
        contentStack.addArrangedSubview(makeFieldRow(title: "name", field: nameField, placeholder: "checkout"))
        contentStack.addArrangedSubview(makeFieldRow(title: "labels", field: labelsField, placeholder: "key=value, key2=value2"))

        let manualRow = UIStackView(arrangedSubviews: [startButton, endButton])
        manualRow.axis = .horizontal
        manualRow.spacing = 8
        manualRow.distribution = .fillEqually
        contentStack.addArrangedSubview(manualRow)

        inFlightLabel.font = .preferredFont(forTextStyle: .footnote)
        inFlightLabel.textColor = .secondaryLabel
        inFlightLabel.numberOfLines = 0
        contentStack.addArrangedSubview(inFlightLabel)

        contentStack.addArrangedSubview(makeSectionHeader("Quick presets"))
        let quickRow = UIStackView(arrangedSubviews: [quick100Button, quick500Button, quick1sButton])
        quickRow.axis = .horizontal
        quickRow.spacing = 8
        quickRow.distribution = .fillEqually
        contentStack.addArrangedSubview(quickRow)

        let quickNote = UILabel()
        quickNote.text = "Each preset starts a measurement, sleeps on a background queue, then ends. Labels: preset=<size>, sleepMs=<n>."
        quickNote.font = .preferredFont(forTextStyle: .caption2)
        quickNote.textColor = .tertiaryLabel
        quickNote.numberOfLines = 0
        contentStack.addArrangedSubview(quickNote)

        contentStack.addArrangedSubview(makeSectionHeader("Captured (tracesExporter)"))
        contentStack.addArrangedSubview(clearButton)

        capturedTable.translatesAutoresizingMaskIntoConstraints = false
        capturedTable.layer.cornerRadius = 10
        capturedTable.layer.borderWidth = 0.5
        capturedTable.layer.borderColor = UIColor.separator.cgColor
        capturedTable.heightAnchor.constraint(equalToConstant: 280).isActive = true
        contentStack.addArrangedSubview(capturedTable)

        nameField.addTarget(self, action: #selector(nameFieldChanged), for: .editingChanged)
        labelsField.addTarget(self, action: #selector(labelsFieldChanged), for: .editingChanged)
    }

    private func refreshFromModel() {
        capturedTable.reloadData()
        appliedConfigLabel.text = model.isApplied
            ? model.appliedConfigDescription
            : "(not applied — tap Apply to reinit the SDK with the tracesExporter)"
        inFlightLabel.text = model.inFlight.isEmpty
            ? "No in-flight timers."
            : "In-flight: \(model.inFlight.sorted().joined(separator: ", "))"
        updateButtonsEnabled()
    }

    private func updateButtonsEnabled() {
        let on = model.isApplied
        for btn in [startButton, endButton, quick100Button, quick500Button, quick1sButton] {
            btn.isEnabled = on
            btn.alpha = on ? 1 : 0.4
        }
    }

    // MARK: - Actions

    @objc private func nameFieldChanged() { model.timerName = nameField.text ?? "" }
    @objc private func labelsFieldChanged() { model.labelsText = labelsField.text ?? "" }

    @objc private func didTapApply()    { showToast(model.apply()) }
    @objc private func didTapStart()    { showToast(model.start()) }
    @objc private func didTapEnd()      { showToast(model.end()) }
    @objc private func didTapQuick100() { showToast(model.runQuick(label: "100ms", sleepMs: 100)) }
    @objc private func didTapQuick500() { showToast(model.runQuick(label: "500ms", sleepMs: 500)) }
    @objc private func didTapQuick1s()  { showToast(model.runQuick(label: "1s", sleepMs: 1000)) }
    @objc private func didTapClear()    { model.clearCaptured() }

    // MARK: - View builders

    private func makeSectionHeader(_ title: String) -> UIView {
        let l = UILabel()
        l.text = title
        l.font = .preferredFont(forTextStyle: .headline)
        return l
    }

    private func makeFieldRow(title: String, field: UITextField, placeholder: String) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.widthAnchor.constraint(equalToConstant: 60).isActive = true

        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.autocorrectionType = .no
        field.autocapitalizationType = .none

        let row = UIStackView(arrangedSubviews: [label, field])
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

extension TimeMeasurementViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(model.captured.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "captured", for: indexPath)
        cell.selectionStyle = .none
        var config = UIListContentConfiguration.subtitleCell()
        if model.captured.isEmpty {
            config.text = "(no spans yet — apply, then trigger a measurement)"
            config.textProperties.color = .secondaryLabel
            config.textProperties.font = .preferredFont(forTextStyle: .footnote)
        } else {
            let row = model.captured[indexPath.row]
            config.text = "\(row.name)  ·  \(row.durationString)"
            var subtitle = row.timeString
            if !row.labelsString.isEmpty {
                subtitle += "  ·  \(row.labelsString)"
            }
            config.secondaryText = subtitle
            config.textProperties.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            config.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption2)
            config.secondaryTextProperties.color = .secondaryLabel
        }
        cell.contentConfiguration = config
        return cell
    }
}
