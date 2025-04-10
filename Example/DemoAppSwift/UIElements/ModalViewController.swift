//
//  ModalViewController.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 21/05/2024.
//

import UIKit

class ModalViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the background color to differentiate
        view.backgroundColor = .white
        
        // Configure additional UI elements here
        setupUI()
    }
    
    private func setupUI() {
        // Create and configure a label
        let label = UILabel()
        label.text = "Hello, I'm Modal View!"
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        
        let button = UIButton(type: .system)
        button.setTitle("Dissmis", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        #if os(iOS)
        button.addTarget(self, action: #selector(dismissViewController), for: .touchUpInside)
        #else
        button.addTarget(self, action: #selector(dismissViewController), for: .primaryActionTriggered)
        #endif
        // Add the label to the view
        view.addSubview(label)
        view.addSubview(button)

        // Set constraints for the label
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        // Set constraints for the button
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 20)
        ])
    }
    
    @objc private func dismissViewController() {
        if self.presentingViewController != nil {
            self.dismiss(animated: true, completion: nil)
        } else {
            print("ModalViewController was not presented modally.")
        }
    }
}
