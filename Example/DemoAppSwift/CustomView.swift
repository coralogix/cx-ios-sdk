//
//  CustomView.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 20/08/2024.
//

import UIKit

class CustomView: UIView {
    
    private let label = UILabel()
    private let scrollView = UIScrollView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        // Set the view's background color
        self.backgroundColor = .white
        
        // Configure the UIScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        
        // Configure the UILabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0 // Allows the label to have multiple lines (word wrapping)
        label.font = UIFont.systemFont(ofSize: 16)
        label.textAlignment = .natural // Align text according to the language's natural direction
        
        // Add the label to the scroll view
        scrollView.addSubview(label)
        
        // Add the scroll view to the custom view
        self.addSubview(scrollView)
        
        // Set up constraints for the scroll view
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: self.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
        
        // Set up constraints for the label within the scroll view
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            label.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32) // Ensure label width matches scroll view
        ])
    }
    
    func updateText(_ text: String) {
        label.text =  (label.text ?? "") + "\n\(text)"
    }
}
