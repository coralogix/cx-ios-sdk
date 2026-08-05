//
//  MaskViewController.swift
//  DemoAppSwift
//
//  Created by Tomer Har Yoffi on 05/11/2025.
//

import Foundation
import UIKit

class MaskViewController: UIViewController {
    
    // MARK: - UI Elements
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Mask Demo Page"
        label.font = .boldSystemFont(ofSize: 24)
        label.textAlignment = .center
        label.cxMask = true // 👈 masked examples
        return label
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "This screen contains common UIKit components.\nYou can toggle cxMask on any of them."
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.cxMask = true // 👈 masked examples
        return label
    }()
    
    private let usernameField: UITextField = {
        let field = UITextField()
        field.placeholder = "Username"
        field.borderStyle = .roundedRect
        field.cxMask = true // 👈 masked example
        return field
    }()
    
    private let passwordField: UITextField = {
        let field = UITextField()
        field.placeholder = "Password"
        field.isSecureTextEntry = true
        field.borderStyle = .roundedRect
        field.cxMask = true // 👈 masked example
        return field
    }()
    
    private let textView: UITextView = {
        let tv = UITextView()
        tv.text = "Enter some text here..."
        tv.font = .systemFont(ofSize: 15)
        tv.layer.borderWidth = 1
        tv.layer.borderColor = UIColor.systemGray4.cgColor
        tv.layer.cornerRadius = 8
        return tv
    }()
    
    private let button: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Submit", for: .normal)
        btn.backgroundColor = .systemBlue
        btn.tintColor = .white
        btn.layer.cornerRadius = 8
        btn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        btn.cxMask = true // 👈 masked example
        return btn
    }()
    
    private let toggleSwitch: UISwitch = {
        let sw = UISwitch()
        sw.cxMask = true // 👈 masked example
        return sw
    }()
    
    private let slider: UISlider = {
        let sl = UISlider()
        sl.minimumValue = 0
        sl.maximumValue = 100
        sl.value = 50
        sl.cxMask = true  // 👈 masked example
        return sl
    }()
    
    private let imageView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "person.circle.fill"))
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .systemTeal
        iv.layer.cornerRadius = 40
        iv.clipsToBounds = true
        iv.cxMask = true // 👈 masked example
        return iv
    }()
    
    private let segmentedControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["One", "Two", "Three"])
        sc.selectedSegmentIndex = 0
        return sc
    }()
    
    private let stepper: UIStepper = {
        let st = UIStepper()
        st.minimumValue = 0
        st.maximumValue = 10
        st.value = 5
        st.cxMask = true // 👈 masked example
        return st
    }()
    
    private let progressView: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .default)
        pv.progress = 0.4
        pv.cxMask = true  // 👈 masked example
        return pv
    }()
    
    private let maskedLabel: UILabel = {
        let label = UILabel()
        label.text = "Sensitive Info"
        label.textColor = .systemRed
        label.cxMask = true // 👈 masked example
        return label
    }()

    private let keypadCaption: UILabel = {
        let label = UILabel()
        label.text = "Keypads: the left one is masked at the container. "
            + "Tap both and compare them in the replay."
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    /// Masking is applied to the container only — the keys inside carry no `cxMask` of their own.
    /// They still inherit it: the replay draws no tap marker over them and their interaction
    /// events report `***` instead of the digit.
    private lazy var maskedKeypad: UIView = {
        let keypad = makeKeypad(tint: .systemRed)
        keypad.cxMask = true // 👈 masks the whole subtree, keys included
        return keypad
    }()

    /// The same keypad without masking — its digits appear in the replay and in the interaction
    /// events, which is what makes the masked one's behaviour visible as a difference.
    private lazy var unmaskedKeypad: UIView = makeKeypad(tint: .systemBlue)

    private func makeKeypad(tint: UIColor) -> UIView {
        let rows = (0..<2).map { row -> UIStackView in
            let buttons = (0..<3).map { column -> UIButton in
                let digit = row * 3 + column + 1
                let key = UIButton(type: .system)
                key.setTitle("\(digit)", for: .normal)
                key.titleLabel?.font = .boldSystemFont(ofSize: 20)
                key.tintColor = tint
                key.layer.borderWidth = 1
                key.layer.borderColor = tint.withAlphaComponent(0.4).cgColor
                key.layer.cornerRadius = 6
                key.accessibilityIdentifier = "keypad_key_\(digit)"
                key.addTarget(self, action: #selector(keypadKeyTapped(_:)), for: .touchUpInside)
                return key
            }
            let rowStack = UIStackView(arrangedSubviews: buttons)
            rowStack.axis = .horizontal
            rowStack.spacing = 6
            rowStack.distribution = .fillEqually
            return rowStack
        }

        let keypad = UIStackView(arrangedSubviews: rows)
        keypad.axis = .vertical
        keypad.spacing = 6
        keypad.distribution = .fillEqually
        keypad.heightAnchor.constraint(equalToConstant: 92).isActive = true
        return keypad
    }

    @objc private func keypadKeyTapped(_ sender: UIButton) {
        sender.alpha = 0.4
        UIView.animate(withDuration: 0.2) { sender.alpha = 1.0 }
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupLayout()
    }
    
    // MARK: - Layout
    private func setupLayout() {
        let keypadRow = UIStackView(arrangedSubviews: [maskedKeypad, unmaskedKeypad])
        keypadRow.axis = .horizontal
        keypadRow.spacing = 16
        keypadRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            descriptionLabel,
            usernameField,
            passwordField,
            textView,
            maskedLabel,
            keypadCaption,
            keypadRow,
            button,
            toggleSwitch,
            slider,
            segmentedControl,
            stepper,
            progressView,
            imageView
        ])

        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Scrolls because the content no longer fits a single screen once the keypads are added.
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),

            textView.heightAnchor.constraint(equalToConstant: 100),
            imageView.heightAnchor.constraint(equalToConstant: 80)
        ])
    }
}
