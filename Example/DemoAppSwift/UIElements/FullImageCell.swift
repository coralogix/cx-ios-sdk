//
//  FullImageCell.swift
//  DemoAppSwift
//
//  Created by Tomer Har Yoffi on 23/11/2025.
//

import UIKit
class FullImageCell: UITableViewCell {

    private let cardView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 16
        v.layer.masksToBounds = true
        return v
    }()

    private let shadowView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.15
        v.layer.shadowRadius = 8
        v.layer.shadowOffset = CGSize(width: 0, height: 3)
        return v
    }()

    private let imageViewCell: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        return iv
    }()

    private var aspectConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(shadowView)
        shadowView.addSubview(cardView)
        cardView.addSubview(imageViewCell)

        NSLayoutConstraint.activate([
            shadowView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            shadowView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            shadowView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            shadowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),

            cardView.leadingAnchor.constraint(equalTo: shadowView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: shadowView.trailingAnchor),
            cardView.topAnchor.constraint(equalTo: shadowView.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: shadowView.bottomAnchor),

            imageViewCell.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            imageViewCell.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            imageViewCell.topAnchor.constraint(equalTo: cardView.topAnchor),
            imageViewCell.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
        ])
    }

    func configure(with imageName: String) {
        guard let image = UIImage(named: imageName) else { return }
        imageViewCell.image = image

        // Remove previous aspect ratio constraint if exists
        aspectConstraint?.isActive = false

        // Compute new multiplier based on real image ratio
        let ratio = image.size.height / image.size.width

        aspectConstraint = imageViewCell.heightAnchor.constraint(
            equalTo: imageViewCell.widthAnchor,
            multiplier: ratio
        )

        aspectConstraint?.priority = .required
        aspectConstraint?.isActive = true
    }
}
