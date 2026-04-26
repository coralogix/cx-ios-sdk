//
//  CustomSpansViewController.swift
//  DemoAppSwift
//
//  Manual exercises for CoralogixCustomTracer / CoralogixGlobalSpan / CoralogixCustomSpan.
//

import UIKit
import Coralogix

final class CustomSpansViewController: UITableViewController {

    // MARK: - Returns log

    private struct ReturnEntry {
        let operation: String
        var fields: [(key: String, value: String)]

        var jsonObject: [String: String] {
            var d: [String: String] = ["operation": operation]
            for f in fields { d[f.key] = f.value }
            return d
        }

        var formattedText: String {
            var lines = ["operation: \"\(operation)\""]
            for f in fields { lines.append("\(f.key): \"\(f.value)\"") }
            return "{\n" + lines.map { "  " + $0 }.joined(separator: ",\n") + "\n}"
        }
    }

    private var returnsLog: [ReturnEntry] = []

    private func logReturn(_ entry: ReturnEntry) {
        DispatchQueue.main.async {
            self.returnsLog.append(entry)
            let section = 2
            let row = self.returnsLog.count - 1
            let wasEmpty = row == 0
            if wasEmpty {
                self.tableView.reloadSections(IndexSet(integer: section), with: .automatic)
            } else {
                self.tableView.insertRows(at: [IndexPath(row: row, section: section)], with: .automatic)
            }
        }
    }

    private func clearReturns() {
        returnsLog.removeAll()
        tableView.reloadSections(IndexSet(integer: 2), with: .automatic)
    }

    private func copyReturnsJson() {
        let array = returnsLog.map { $0.jsonObject }
        guard let data = try? JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        UIPasteboard.general.string = json
        presentToast("Copied \(returnsLog.count) return(s) as JSON")
    }

    // MARK: - Demo items

    /// CX-35956: `getCustomTracer()` succeeds only once per SDK session; reuse for all rows.
    private var cachedCustomTracer: CoralogixCustomTracer?
    /// Whether the cached tracer was created with `ignoredInstruments: [.networkRequests, .errors]` (`true`) or `[]` (`false`).
    private var cachedTracerPreferIgnored: Bool?

    private struct DemoItem {
        let title: String
        let subtitle: String
        let systemImageName: String
        let action: () -> Void
    }

    /// Shown above the list so the demos make sense without reading SDK docs.
    private static let introAttributedText: NSAttributedString = {
        let body = UIFont.preferredFont(forTextStyle: .footnote)
        let bold = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .footnote)
            .withSymbolicTraits(.traitBold)
        let boldFont = bold.map { UIFont(descriptor: $0, size: 0) } ?? body

        let s = NSMutableAttributedString()
        func add(_ text: String, font: UIFont) {
            s.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.secondaryLabel]))
        }

        add("What you're looking at\n", font: boldFont)
        add(
            "Custom spans are manual RUM spans (exported like the Browser SDK, type custom-span). "
                + "A global span is the \"root\" for a flow; nested spans are children. "
                + "Only one global may exist at a time.\n\n",
            font: body
        )
        add("Why \"global\" matters\n", font: boldFont)
        add(
            "startGlobalSpan registers that span as OpenTelemetry's active context. "
                + "Auto-instrumentation (e.g. URLSession) can then use the same traceId until you call endSpan(), "
                + "which restores the previous active span.\n\n",
            font: body
        )
        add("withContext\n", font: boldFont)
        add(
            "Runs a closure while the global is the logical \"current\" span. "
                + "If the global is already the active OTel span (right after startGlobalSpan), the SDK does not swap context—it just runs your code.\n\n",
            font: body
        )
        add("Tap a row below to run a scripted sequence; check Coralogix for span names and the shared trace.",
            font: body
        )
        return s
    }()

    private lazy var items: [DemoItem] = [
        DemoItem(
            title: "Simple global + child spans",
            subtitle:
                "Simulates a small user flow: startGlobalSpan → startCustomSpan (child) → set attribute, event, status → end child → end global. "
                + "You should see two custom-span events on one trace in Coralogix.",
            systemImageName: "point.3.connected.trianglepath.dotted",
            action: { [weak self] in self?.runSimpleFlow(useIgnoredTracer: false) }
        ),
        DemoItem(
            title: "withContext + GET request",
            subtitle:
                "Simulates doing work (here a demo GET) while the global span is open. "
                + "Shows that withContext is safe when the global is already active; the HTTP span should still relate to the same trace as the global.",
            systemImageName: "network",
            action: { [weak self] in self?.runWithContextNetwork() }
        ),
        DemoItem(
            title: "Second startGlobalSpan rejected",
            subtitle:
                "Simulates the Browser rule: with a global still open, a second startGlobalSpan returns nil (no second root). "
                + "After endSpan(), a new global can start—proves the slot was released.",
            systemImageName: "exclamationmark.triangle",
            action: { [weak self] in self?.runSecondGlobalRejectedDemo() }
        ),
        DemoItem(
            title: "Tracer with ignoredInstruments",
            subtitle:
                "Same span sequence as the first row, but using getCustomTracer(ignoredInstruments: [.networkRequests, .errors]). "
                + "Today this matches the default tracer; the set is reserved for future control over how auto-instrumentation joins custom context.",
            systemImageName: "eye.slash",
            action: { [weak self] in self?.runSimpleFlow(useIgnoredTracer: true) }
        )
    ]

    // MARK: - Lifecycle

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Custom Spans"
        navigationController?.navigationBar.prefersLargeTitles = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "introCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "returnCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "emptyCell")
        tableView.rowHeight = UITableView.automaticDimension
        // Long subtitles; estimates far below real height break UITableView content sizing (gaps / clipped rows).
        tableView.estimatedRowHeight = 220
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return items.count
        case 2: return max(returnsLog.count, 1) // 1 = empty state cell
        default: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 ? "Demos" : nil
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == 2 else { return nil }

        let container = UIView()
        container.backgroundColor = .clear

        let label = UILabel()
        label.text = "Returns"
        label.font = UIFont.preferredFont(forTextStyle: .footnote).withBold()
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        let copyBtn = UIButton(type: .system)
        copyBtn.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copyBtn.setTitle(" Copy JSON", for: .normal)
        copyBtn.titleLabel?.font = UIFont.preferredFont(forTextStyle: .footnote)
        copyBtn.addTarget(self, action: #selector(didTapCopyJson), for: .touchUpInside)
        copyBtn.translatesAutoresizingMaskIntoConstraints = false
        copyBtn.isHidden = returnsLog.isEmpty

        let clearBtn = UIButton(type: .system)
        clearBtn.setImage(UIImage(systemName: "trash"), for: .normal)
        clearBtn.tintColor = .systemRed
        clearBtn.addTarget(self, action: #selector(didTapClear), for: .touchUpInside)
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        clearBtn.isHidden = returnsLog.isEmpty

        container.addSubview(label)
        container.addSubview(copyBtn)
        container.addSubview(clearBtn)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            clearBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            clearBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            copyBtn.trailingAnchor.constraint(equalTo: clearBtn.leadingAnchor, constant: -4),
            copyBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 36)
        ])

        return container
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == 2 ? 36 : UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "introCell", for: indexPath)
            cell.selectionStyle = .none
            cell.accessoryType = .none
            var config = UIListContentConfiguration.cell()
            config.attributedText = Self.introAttributedText
            config.textProperties.numberOfLines = 0
            cell.contentConfiguration = config
            return cell
        }

        if indexPath.section == 1 {
            let item = items[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            var config = UIListContentConfiguration.subtitleCell()
            config.text = item.title
            config.secondaryText = item.subtitle
            config.image = UIImage(systemName: item.systemImageName)
            config.imageProperties.preferredSymbolConfiguration =
                UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            config.secondaryTextProperties.color = .secondaryLabel
            config.secondaryTextProperties.numberOfLines = 0
            cell.contentConfiguration = config
            cell.accessoryType = .none
            return cell
        }

        // Section 2 — Returns log
        if returnsLog.isEmpty {
            let cell = tableView.dequeueReusableCell(withIdentifier: "emptyCell", for: indexPath)
            cell.selectionStyle = .none
            var config = UIListContentConfiguration.cell()
            config.text = "Tap a demo row above — span return values (spanId, traceId) will appear here."
            config.textProperties.color = .tertiaryLabel
            config.textProperties.font = UIFont.preferredFont(forTextStyle: .footnote)
            config.textProperties.numberOfLines = 0
            cell.contentConfiguration = config
            return cell
        }

        let entry = returnsLog[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "returnCell", for: indexPath)
        cell.selectionStyle = .none

        var config = UIListContentConfiguration.subtitleCell()
        config.text = entry.operation
        config.textProperties.font = UIFont.preferredFont(forTextStyle: .footnote).withBold()
        config.textProperties.color = .systemBlue
        config.secondaryText = entry.formattedText
        config.secondaryTextProperties.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        config.secondaryTextProperties.color = .secondaryLabel
        config.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        items[indexPath.row].action()
    }

    // MARK: - Header button actions

    @objc private func didTapCopyJson() { copyReturnsJson() }
    @objc private func didTapClear() { clearReturns() }

    // MARK: - Demos

    /// First successful `getCustomTracer` wins for the session (CX-35956). If another row already obtained a tracer with a different `ignoredInstruments`, that tracer is reused.
    private func tracerForSession(preferIgnored: Bool) -> CoralogixCustomTracer? {
        if let c = cachedCustomTracer {
            if (cachedTracerPreferIgnored ?? false) != preferIgnored {
                presentToast(
                    "Reusing the tracer from an earlier demo — ignored-instruments setting differs. Relaunch the app to switch tracer configuration."
                )
            }
            return c
        }
        let rum = CoralogixRumManager.shared.sdk
        let t: CoralogixCustomTracer?
        if preferIgnored {
            t = rum.getCustomTracer(ignoredInstruments: [.networkRequests, .errors])
        } else {
            t = rum.getCustomTracer()
        }
        guard let tracer = t else {
            presentToast("Custom tracer unavailable — set traceParentInHeader with enable: true in SDK options.")
            return nil
        }
        cachedCustomTracer = tracer
        cachedTracerPreferIgnored = preferIgnored
        return tracer
    }

    private func runSimpleFlow(useIgnoredTracer: Bool) {
        let rum = CoralogixRumManager.shared.sdk
        guard rum.isInitialized else { presentToast("SDK not initialized"); return }
        guard let tracer = tracerForSession(preferIgnored: useIgnoredTracer) else { return }

        guard let global = tracer.startGlobalSpan(
            name: "demo.custom.global",
            labels: ["demo.screen": "CustomSpans"]
        ) else {
            presentToast("startGlobalSpan returned nil")
            return
        }
        logReturn(ReturnEntry(operation: "startGlobalSpan", fields: [
            ("name", "demo.custom.global"),
            ("spanId", global.spanId),
            ("traceId", global.traceId)
        ]))

        let child = global.startCustomSpan(name: "demo.custom.child")
        logReturn(ReturnEntry(operation: "startCustomSpan", fields: [
            ("name", "demo.custom.child"),
            ("spanId", child.span.context.spanId.hexString),
            ("traceId", child.span.context.traceId.hexString)
        ]))

        child.setAttribute(key: "demo.step", value: "authorize")
        child.addEvent(name: "demo.checkpoint")
        child.setStatus(.ok)
        child.endSpan()
        logReturn(ReturnEntry(operation: "endSpan", fields: [("spanId", child.span.context.spanId.hexString)]))

        global.endSpan()
        logReturn(ReturnEntry(operation: "endSpan", fields: [("spanId", global.spanId)]))

        presentToast(useIgnoredTracer ? "Finished (ignored-instruments tracer)" : "Finished simple flow")
    }

    private func runSecondGlobalRejectedDemo() {
        let rum = CoralogixRumManager.shared.sdk
        guard rum.isInitialized else { presentToast("SDK not initialized"); return }
        guard let tracer = tracerForSession(preferIgnored: false) else { return }

        guard let first = tracer.startGlobalSpan(name: "demo.custom.first_global") else {
            presentToast("Unexpected: first startGlobalSpan failed")
            return
        }
        logReturn(ReturnEntry(operation: "startGlobalSpan", fields: [
            ("name", "demo.custom.first_global"),
            ("spanId", first.spanId),
            ("traceId", first.traceId)
        ]))

        let second = tracer.startGlobalSpan(name: "demo.custom.should_fail")
        logReturn(ReturnEntry(operation: "startGlobalSpan", fields: [
            ("name", "demo.custom.should_fail"),
            ("result", second == nil ? "null (expected — another global is active)" : "unexpectedly succeeded")
        ]))
        if let s = second {
            presentToast("Bug: second startGlobalSpan should return nil")
            s.endSpan()
            return
        }

        first.endSpan()
        logReturn(ReturnEntry(operation: "endSpan", fields: [("spanId", first.spanId)]))

        guard let after = tracer.startGlobalSpan(name: "demo.custom.after_end") else {
            presentToast("Unexpected: global after endSpan should succeed")
            return
        }
        logReturn(ReturnEntry(operation: "startGlobalSpan", fields: [
            ("name", "demo.custom.after_end"),
            ("spanId", after.spanId),
            ("traceId", after.traceId)
        ]))

        after.endSpan()
        logReturn(ReturnEntry(operation: "endSpan", fields: [("spanId", after.spanId)]))

        presentToast("OK: 2nd global rejected; new global after endSpan works")
    }

    private func runWithContextNetwork() {
        let rum = CoralogixRumManager.shared.sdk
        guard rum.isInitialized else { presentToast("SDK not initialized"); return }
        guard let tracer = tracerForSession(preferIgnored: false) else { return }

        guard let global = tracer.startGlobalSpan(
            name: "demo.custom.with_context",
            labels: ["demo.flow": "network"]
        ) else {
            presentToast("startGlobalSpan returned nil")
            return
        }
        logReturn(ReturnEntry(operation: "startGlobalSpan", fields: [
            ("name", "demo.custom.with_context"),
            ("spanId", global.spanId),
            ("traceId", global.traceId)
        ]))

        global.withContext {
            NetworkSim.sendSuccesfullRequest()
        }

        global.endSpan()
        logReturn(ReturnEntry(operation: "endSpan", fields: [("spanId", global.spanId)]))

        presentToast("GET started under withContext; global span ended")
    }

    private func presentToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            alert.dismiss(animated: true)
        }
    }
}

// MARK: - UIFont helper

private extension UIFont {
    func withBold() -> UIFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.traitBold)
        return descriptor.map { UIFont(descriptor: $0, size: 0) } ?? self
    }
}
