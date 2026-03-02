//
//  PageController.swift
//  DemoAppSwift
//
//  Created by Coralogix Dev Team on 28/07/2024.
//

import UIKit

class PageController: UIViewController, UIScrollViewDelegate {

    // MARK: - Properties

    private var scrollView: UIScrollView!
    private var pageControl: UIPageControl!
    private var feedbackGenerator: UIImpactFeedbackGenerator?

    private struct PageData {
        let title: String
        let subtitle: String
        let metric: String
        let unit: String
        let icon: String
        let topColor: UIColor
        let bottomColor: UIColor
    }

    private let pages: [PageData] = [
        PageData(
            title: "Overview",
            subtitle: "Active sessions right now",
            metric: "1,284",
            unit: "sessions",
            icon: "chart.bar.fill",
            topColor: UIColor(red: 0.42, green: 0.39, blue: 1.00, alpha: 1),
            bottomColor: UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1)
        ),
        PageData(
            title: "Sessions",
            subtitle: "Average session duration",
            metric: "4m 32s",
            unit: "per user",
            icon: "clock.fill",
            topColor: UIColor(red: 0.06, green: 0.72, blue: 0.51, alpha: 1),
            bottomColor: UIColor(red: 0.05, green: 0.65, blue: 0.91, alpha: 1)
        ),
        PageData(
            title: "Performance",
            subtitle: "P99 response time",
            metric: "142ms",
            unit: "excellent",
            icon: "bolt.fill",
            topColor: UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1),
            bottomColor: UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1)
        )
    ]

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Dashboard"
        view.backgroundColor = .systemBackground
        feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        feedbackGenerator?.prepare()
        setupScrollView()
        setupPageControl()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = scrollView.bounds.width
        guard w > 0 else { return }
        // Rebuild whenever the expected content width doesn't match the current one.
        // This covers both the initial layout and device rotation (bounds change).
        let expectedContentWidth = w * CGFloat(pages.count)
        guard scrollView.contentSize.width != expectedContentWidth else { return }

        let currentPage = pageControl.currentPage
        scrollView.subviews.forEach { $0.removeFromSuperview() }
        layoutPages()
        // Restore the visible page after rebuild so rotation feels seamless.
        scrollView.contentOffset = CGPoint(x: CGFloat(currentPage) * w, y: 0)
    }

    // MARK: - Scroll view

    private func setupScrollView() {
        scrollView = UIScrollView()
        scrollView.delegate = self
        scrollView.accessibilityIdentifier = "pageControllerScrollView"
#if os(iOS)
        scrollView.isPagingEnabled = true
#endif
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Page control

    private func setupPageControl() {
        pageControl = UIPageControl()
        pageControl.numberOfPages = pages.count
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = .white
        pageControl.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.4)
        pageControl.addTarget(self, action: #selector(pageControlChanged(_:)), for: .valueChanged)
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageControl)

        NSLayoutConstraint.activate([
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    // MARK: - Page layout

    private func layoutPages() {
        let w = scrollView.bounds.width
        let h = scrollView.bounds.height
        scrollView.contentSize = CGSize(width: w * CGFloat(pages.count), height: h)

        for (i, data) in pages.enumerated() {
            let pageView = buildPageView(index: i, width: w, height: h, data: data)
            scrollView.addSubview(pageView)
        }
    }

    private func buildPageView(index: Int, width: CGFloat, height: CGFloat, data: PageData) -> UIView {
        let container = UIView(frame: CGRect(x: CGFloat(index) * width, y: 0, width: width, height: height))

        // Full-bleed diagonal gradient
        let gradient = CAGradientLayer()
        gradient.frame = container.bounds
        gradient.colors = [data.topColor.cgColor, data.bottomColor.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint   = CGPoint(x: 1, y: 1)
        container.layer.insertSublayer(gradient, at: 0)

        // Decorative ambient blobs
        addBlobs(to: container, width: width, height: height)

        // Glassmorphic metric card
        let card = buildCard(data: data)
        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -24),
            card.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.84),
            card.heightAnchor.constraint(equalToConstant: 312)
        ])

        return container
    }

    private func addBlobs(to parent: UIView, width: CGFloat, height: CGFloat) {
        let specs: [(CGRect, CGFloat)] = [
            (CGRect(x: -70, y: -70, width: 220, height: 220), 0.13),
            (CGRect(x: width - 110, y: height - 210, width: 250, height: 250), 0.09),
            (CGRect(x: width * 0.30, y: height * 0.07, width: 130, height: 130), 0.07)
        ]
        for (frame, alpha) in specs {
            let blob = UIView(frame: frame)
            blob.backgroundColor = UIColor.white.withAlphaComponent(alpha)
            blob.layer.cornerRadius = min(frame.width, frame.height) / 2
            parent.addSubview(blob)
        }
    }

    private func buildCard(data: PageData) -> UIView {
        let card = UIView()
        card.layer.cornerRadius = 32
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor

        let (blur, tint) = addGlassLayers(to: card)
        let (iconView, metricLabel, unitLabel) = addMetricViews(to: card, data: data)
        let (divider, titleLabel, subtitleLabel) = addLabelViews(to: card, data: data)

        activateCardConstraints(
            card: card,
            blur: blur, tint: tint,
            iconView: iconView,
            metricLabel: metricLabel, unitLabel: unitLabel,
            divider: divider,
            titleLabel: titleLabel, subtitleLabel: subtitleLabel
        )

        return card
    }

    private func addGlassLayers(to card: UIView) -> (UIVisualEffectView, UIView) {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
        blur.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(blur)

        let tint = UIView()
        tint.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        tint.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(tint)

        return (blur, tint)
    }

    private func addMetricViews(to card: UIView, data: PageData) -> (UIImageView, UILabel, UILabel) {
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 44, weight: .semibold)
        let iconView = UIImageView(image: UIImage(systemName: data.icon, withConfiguration: iconConfig))
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(iconView)

        let metricLabel = UILabel()
        metricLabel.text = data.metric
        metricLabel.font = UIFont.systemFont(ofSize: 52, weight: .heavy)
        metricLabel.textColor = .white
        metricLabel.textAlignment = .center
        metricLabel.adjustsFontSizeToFitWidth = true
        metricLabel.minimumScaleFactor = 0.6
        metricLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(metricLabel)

        let unitLabel = UILabel()
        unitLabel.attributedText = NSAttributedString(
            string: data.unit.uppercased(),
            attributes: [
                .kern: CGFloat(1.8),
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.65)
            ]
        )
        unitLabel.textAlignment = .center
        unitLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(unitLabel)

        return (iconView, metricLabel, unitLabel)
    }

    private func addLabelViews(to card: UIView, data: PageData) -> (UIView, UILabel, UILabel) {
        let divider = UIView()
        divider.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        divider.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(divider)

        let titleLabel = UILabel()
        titleLabel.text = data.title
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.text = data.subtitle
        subtitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(subtitleLabel)

        return (divider, titleLabel, subtitleLabel)
    }

    private func activateCardConstraints(
        card: UIView,
        blur: UIVisualEffectView, tint: UIView,
        iconView: UIImageView,
        metricLabel: UILabel, unitLabel: UILabel,
        divider: UIView,
        titleLabel: UILabel, subtitleLabel: UILabel
    ) {
        NSLayoutConstraint.activate([
            // Glass layers fill the card
            blur.topAnchor.constraint(equalTo: card.topAnchor),
            blur.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            tint.topAnchor.constraint(equalTo: card.topAnchor),
            tint.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            // Icon — top-center
            iconView.topAnchor.constraint(equalTo: card.topAnchor, constant: 36),
            iconView.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 60),
            iconView.heightAnchor.constraint(equalToConstant: 60),

            // Big number
            metricLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 18),
            metricLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            metricLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),

            // Unit
            unitLabel.topAnchor.constraint(equalTo: metricLabel.bottomAnchor, constant: 4),
            unitLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            unitLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),

            // Divider
            divider.topAnchor.constraint(equalTo: unitLabel.bottomAnchor, constant: 22),
            divider.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            divider.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            divider.heightAnchor.constraint(equalToConstant: 1),

            // Title
            titleLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),

            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24)
        ])
    }

    // MARK: - Actions

    @objc private func pageControlChanged(_ sender: UIPageControl) {
        let offset = CGFloat(sender.currentPage) * scrollView.bounds.width
        scrollView.setContentOffset(CGPoint(x: offset, y: 0), animated: true)
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
        guard pageControl.currentPage != page else { return }
        pageControl.currentPage = page
        feedbackGenerator?.impactOccurred()
        feedbackGenerator?.prepare()
    }
}
