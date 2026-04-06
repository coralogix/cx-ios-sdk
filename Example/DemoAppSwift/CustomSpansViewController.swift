//
//  CustomSpansViewController.swift
//  DemoAppSwift
//
//  Manual exercises for CoralogixCustomTracer / CoralogixGlobalSpan / CoralogixCustomSpan.
//

import UIKit
import Coralogix

final class CustomSpansViewController: UITableViewController {

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

        add("What you’re looking at\n", font: boldFont)
        add(
            "Custom spans are manual RUM spans (exported like the Browser SDK, type custom-span). "
                + "A global span is the “root” for a flow; nested spans are children. "
                + "Only one global may exist at a time.\n\n",
            font: body
        )
        add("Why “global” matters\n", font: boldFont)
        add(
            "startGlobalSpan registers that span as OpenTelemetry’s active context. "
                + "Auto-instrumentation (e.g. URLSession) can then use the same traceId until you call endSpan(), "
                + "which restores the previous active span.\n\n",
            font: body
        )
        add("withContext\n", font: boldFont)
        add(
            "Runs a closure while the global is the logical “current” span. "
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
        tableView.rowHeight = UITableView.automaticDimension
        // Long subtitles; estimates far below real height break UITableView content sizing (gaps / clipped rows).
        tableView.estimatedRowHeight = 220
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : items.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 ? "Demos" : nil
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

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        items[indexPath.row].action()
    }

    // MARK: - Demos

    private func runSimpleFlow(useIgnoredTracer: Bool) {
        let rum = CoralogixRumManager.shared.sdk
        guard rum.isInitialized else {
            presentToast("SDK not initialized")
            return
        }
        let tracer: CoralogixCustomTracer
        if useIgnoredTracer {
            tracer = rum.getCustomTracer(ignoredInstruments: [.networkRequests, .errors])
        } else {
            tracer = rum.getCustomTracer()
        }
        guard let global = tracer.startGlobalSpan(
            name: "demo.custom.global",
            labels: ["demo.screen": "CustomSpans"]
        ) else {
            presentToast("startGlobalSpan returned nil")
            return
        }
        let child = global.startCustomSpan(name: "demo.custom.child")
        child.setAttribute(key: "demo.step", value: "authorize")
        child.addEvent(name: "demo.checkpoint")
        child.setStatus(.ok)
        child.endSpan()
        global.endSpan()
        presentToast(useIgnoredTracer ? "Finished (ignored-instruments tracer)" : "Finished simple flow")
    }

    private func runSecondGlobalRejectedDemo() {
        let rum = CoralogixRumManager.shared.sdk
        guard rum.isInitialized else {
            presentToast("SDK not initialized")
            return
        }
        let tracer = rum.getCustomTracer()
        guard let first = tracer.startGlobalSpan(name: "demo.custom.first_global") else {
            presentToast("Unexpected: first startGlobalSpan failed")
            return
        }
        if tracer.startGlobalSpan(name: "demo.custom.should_fail") != nil {
            presentToast("Bug: second startGlobalSpan should return nil")
            first.endSpan()
            return
        }
        first.endSpan()
        guard let after = tracer.startGlobalSpan(name: "demo.custom.after_end") else {
            presentToast("Unexpected: global after endSpan should succeed")
            return
        }
        after.endSpan()
        presentToast("OK: 2nd global rejected; new global after endSpan works")
    }

    private func runWithContextNetwork() {
        let rum = CoralogixRumManager.shared.sdk
        guard rum.isInitialized else {
            presentToast("SDK not initialized")
            return
        }
        guard let global = rum.getCustomTracer().startGlobalSpan(
            name: "demo.custom.with_context",
            labels: ["demo.flow": "network"]
        ) else {
            presentToast("startGlobalSpan returned nil")
            return
        }
        global.withContext {
            NetworkSim.sendSuccesfullRequest()
        }
        global.endSpan()
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
