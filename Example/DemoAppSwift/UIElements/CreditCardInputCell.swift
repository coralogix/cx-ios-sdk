//
//  CreditCardInputCell.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 05/12/2024.
//

import UIKit

// Custom cell with UITextView for credit card input
class CreditCardInputCell: UITableViewCell, UITextViewDelegate {
    private let creditCardLabel: UILabel = {
        let label = UILabel()
        label.text = "Credit Card No:"
        label.font = UIFont.systemFont(ofSize: 17)
        return label
    }()
    
    let creditCardTextView: UITextView = {
        let textView = UITextView()
        textView.keyboardType = .numberPad
        textView.font = UIFont.systemFont(ofSize: 17)
        textView.layer.borderColor = UIColor.lightGray.cgColor
        textView.layer.borderWidth = 1.0
        textView.layer.cornerRadius = 5.0
        textView.isScrollEnabled = false
        return textView
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        // Create a horizontal stack view
        let stackView = UIStackView(arrangedSubviews: [creditCardLabel, creditCardTextView])
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(stackView)
        
        // Set constraints for the stack view
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            // Set a fixed width for the label
            creditCardLabel.widthAnchor.constraint(equalToConstant: 120),
            
            // Ensure the text view has a minimum height
            creditCardTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])
        
        creditCardTextView.delegate = self
    }
    
    func textViewDidChange(_ textView: UITextView) {
        // Handle text change and update cell size if needed
        // e.g., format credit card number
    }
}
