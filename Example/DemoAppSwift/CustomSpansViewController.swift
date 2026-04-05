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

    private lazy var items: [DemoItem] = [
        DemoItem(
            title: "Simple global + child spans",
            subtitle: "Labels, attributes, event, status, endSpan",
            systemImageName: "point.3.connected.trianglepath.dotted",
            action: { [weak self] in self?.runSimpleFlow(useIgnoredTracer: false) }
        ),
        DemoItem(
            title: "withContext + GET request",
            subtitle: "Sets active span, then starts jsonplaceholder GET",
            systemImageName: "network",
            action: { [weak self] in self?.runWithContextNetwork() }
        ),
        DemoItem(
            title: "Tracer with ignoredInstruments",
            subtitle: "getCustomTracer(ignoredInstruments: [.networkRequests, .errors])",
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
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = UIListContentConfiguration.subtitleCell()
        config.text = item.title
        config.secondaryText = item.subtitle
        config.image = UIImage(systemName: item.systemImageName)
        config.imageProperties.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        config.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = config
        cell.accessoryType = .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
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
