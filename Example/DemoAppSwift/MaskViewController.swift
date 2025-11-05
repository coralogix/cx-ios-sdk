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
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupLayout()
    }
    
    // MARK: - Layout
    private func setupLayout() {
        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            descriptionLabel,
            usernameField,
            passwordField,
            textView,
            maskedLabel,
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
        
        view.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            
            textView.heightAnchor.constraint(equalToConstant: 100),
            imageView.heightAnchor.constraint(equalToConstant: 80)
        ])
    }
}
