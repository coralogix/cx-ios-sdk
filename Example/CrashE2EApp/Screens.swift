//
//  Screens.swift
//  CrashE2EApp
//
//  Two screens, Home and Second, so a crash has a view to be filed under. Home runs the scenario's
//  actions once it is up, and shows what the test reads back: the session, the stored crashes and
//  whether the actions are done.
//

import UIKit
import Coralogix

class E2EScreen: UIViewController {
    let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    func label(_ identifier: String) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .caption1)
        label.accessibilityIdentifier = identifier
        stack.addArrangedSubview(label)
        return label
    }
}

final class HomeViewController: E2EScreen {
    private var session: UILabel!
    private var store: UILabel!
    private var forwarded: UILabel!
    private var globalTrace: UILabel!
    private var ready: UILabel!
    private var ranActions = false
    private var refresh: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Home"
        session = label("e2e.session")
        store = label("e2e.store")
        forwarded = label("e2e.forwarded")
        globalTrace = label("e2e.globalTrace")
        ready = label("e2e.ready")
        let hang = UIButton(type: .system)
        hang.setTitle("Hang 8 s", for: .normal)
        hang.accessibilityIdentifier = "e2e.hang"
        hang.addAction(UIAction { _ in Thread.sleep(forTimeInterval: 8) }, for: .touchUpInside)
        stack.addArrangedSubview(hang)
        // Last in the stack: the `clicks` action taps the last view.
        let tap = UIButton(type: .system)
        tap.setTitle("Tap me", for: .normal)
        tap.accessibilityIdentifier = "e2e.tap"
        stack.addArrangedSubview(tap)
        update()
        refresh = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.update() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !ranActions else { return }
        ranActions = true
        run(AppDelegate.scenario.actions[...])
    }

    private func update() {
        session.text = AppDelegate.sdk?.getSessionId ?? "none"
        store.text = E2EHooks.storedCrashes()
        forwarded.text = "\(ForwardedCrashes.count)"
        globalTrace.text = AppDelegate.globalTraceId ?? "none"
    }

    /// Runs the actions in order, half a second apart, so each lands after the last one's effects.
    private func run(_ actions: ArraySlice<String>) {
        guard let action = actions.first else {
            ready.text = "ready"
            return
        }
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "crash": E2ECrashes.crash(argument)
        case "hang": Thread.sleep(forTimeInterval: (Double(argument) ?? 6000) / 1000)
        case "hangForever": while true { Thread.sleep(forTimeInterval: 60) }
        case "rotate": AppDelegate.sdk?.createNewSession()
        case "view": navigationController?.pushViewController(SecondViewController(), animated: false)
        case "clicks":
            for _ in 0..<(Int(argument) ?? 1) {
                (stack.arrangedSubviews.last as? UIButton)?.sendActions(for: .touchUpInside)
            }
        case "hybridCrash":
            AppDelegate.sdk?.reportError(message: "crash e2e: hybrid crash", stackTrace: [], errorType: "Error", isCrash: true)
        case "error":
            // An error event (reportError(message:) alone is sent as a log of error severity).
            AppDelegate.sdk?.reportError(message: argument.isEmpty ? "crash e2e: reported error" : argument,
                                         stackTrace: [], errorType: "Error")
        case "wait": break
        default: NSLog("[CrashE2E] unknown action %@", action)
        }
        let delay = parts[0] == "wait" ? (Double(argument) ?? 500) / 1000 : 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.run(actions.dropFirst())
        }
    }
}

final class SecondViewController: E2EScreen {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Second"
        label("e2e.second").text = "Second screen"
    }
}
