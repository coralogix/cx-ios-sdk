//
//  NetworkViewController.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 20/08/2024.
//

import UIKit
import Coralogix

final class NetworkViewController: UITableViewController {

    private struct NetworkItem {
        let title: String
        let subtitle: String
        let systemImageName: String
        let key: Keys
    }

    // MARK: - Data

    private lazy var items: [NetworkItem] = [
        .init(
            title: "Failing network request",
            subtitle: "Simulate a client/server error",
            systemImageName: "xmark.octagon",
            key: .failureNetworkRequest
        ),
        .init(
            title: "Successful network request",
            subtitle: "Standard URLSession request",
            systemImageName: "checkmark.circle",
            key: .succesfullNetworkRequest
        ),
        .init(
            title: "Flutter success request",
            subtitle: "Simulate successful Flutter network",
            systemImageName: "bolt.horizontal.circle",
            key: .succesfullNetworkRequestFlutter
        ),
        .init(
            title: "Flutter failure request",
            subtitle: "Simulate failed Flutter network",
            systemImageName: "bolt.horizontal.circle.fill",
            key: .failureNetworkRequestFlutter
        ),
        .init(
            title: "Alamofire success",
            subtitle: "Successful Alamofire request",
            systemImageName: "bolt.circle",
            key: .succesfullAlamofire
        ),
        .init(
            title: "Alamofire failure",
            subtitle: "Failing Alamofire request",
            systemImageName: "bolt.slash",
            key: .failureAlamofire
        ),
        .init(
            title: "Alamofire upload",
            subtitle: "Upload a 2MB sample file",
            systemImageName: "arrow.up.doc",
            key: .alamofireUploadRequest
        ),
        .init(
            title: "AFNetworking request",
            subtitle: "Legacy AFNetworking example",
            systemImageName: "antenna.radiowaves.left.and.right",
            key: .afnetworkingRequest
        ),
        .init(
            title: "Download image (SDWebImage)",
            subtitle: "Image download & caching",
            systemImageName: "photo.on.rectangle",
            key: .downloadSDWebImage
        ),
        .init(
            title: "POST request",
            subtitle: "Send JSON data to server",
            systemImageName: "arrow.up.circle",
            key: .postRequestToServer
        ),
        .init(
            title: "GET request",
            subtitle: "Fetch data from server",
            systemImageName: "arrow.down.circle",
            key: .getRequestToServer
        ),
        .init(title: "Async/Await example",
              subtitle: "async await in action",
              systemImageName: "photo.on.rectangle",
              key: .signingWithAsyncAwait),
        .init(title: "Async/Await with SSL Pinning",
              subtitle: "async/await + custom delegate",
              systemImageName: "lock.shield",
              key: .asyncAwaitWithSSLPinning)
    ]

    // MARK: - Init

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavigationBar()
        setupTableView()
    }

    // MARK: - UI Setup

    private func setupNavigationBar() {
        title = "Network instrumentation"
        navigationController?.navigationBar.prefersLargeTitles = true
    }

    private func setupTableView() {
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "network_cell")
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 56, bottom: 0, right: 16)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView,
                            numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "network_cell", for: indexPath)

        var config = UIListContentConfiguration.subtitleCell()
        config.text = item.title
        config.secondaryText = item.subtitle
        config.image = UIImage(systemName: item.systemImageName)
        config.imageProperties.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        config.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
        config.secondaryTextProperties.color = .secondaryLabel

        cell.contentConfiguration = config
        cell.accessoryType = .none
        cell.selectionStyle = .default

        return cell
    }

    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView,
                            didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        showToast("Selected: \(item.title)")

        switch item.key {
        case .failureNetworkRequest:
            NetworkSim.failureNetworkRequest()

        case .succesfullNetworkRequest:
            NetworkSim.sendSuccesfullRequest()

        case .succesfullNetworkRequestFlutter:
            NetworkSim.setNetworkRequestContextFlutterSuccsess()

        case .failureNetworkRequestFlutter:
            NetworkSim.setNetworkRequestContextFailure()

        case .succesfullAlamofire:
            NetworkSim.succesfullAlamofire()

        case .failureAlamofire:
            NetworkSim.failureAlamofire()

        case .alamofireUploadRequest:
            let fileUrl = NetworkSim.createSampleFile(sizeInMB: 2)
            NetworkSim.uploadFile(fileURL: fileUrl)

        case .afnetworkingRequest:
            NetworkSim.sendAFNetworkingRequest()

        case .postRequestToServer:
            NetworkSim.performPostRequest()

        case .getRequestToServer:
            NetworkSim.performGetRequest()

        case .downloadSDWebImage:
            NetworkSim.downloadImage()

        case .signingWithAsyncAwait:
            NetworkSim.callAsyncAwait()
        
        case .asyncAwaitWithSSLPinning:
            NetworkSim.callAsyncAwaitWithSSLPinning()
        
        default:
            break
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        let toastLabel = UILabel()
        toastLabel.text = message
        toastLabel.textColor = .white
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toastLabel.textAlignment = .center
        toastLabel.font = .preferredFont(forTextStyle: .subheadline)
        toastLabel.numberOfLines = 0
        toastLabel.alpha = 0.0
        toastLabel.layer.cornerRadius = 12
        toastLabel.layer.masksToBounds = true

        let horizontalScreenMargin: CGFloat = 24
        let horizontalTextPadding: CGFloat = 32
        let verticalTextPadding: CGFloat = 24
        let bottomMargin: CGFloat = 16
        let maxToastHeight: CGFloat = 100

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {

            let maxWidth = keyWindow.bounds.width - 2 * horizontalScreenMargin
            let expectedSize = toastLabel.sizeThatFits(CGSize(width: maxWidth, height: maxToastHeight))
            let width = min(maxWidth, expectedSize.width + horizontalTextPadding)
            let height = expectedSize.height + verticalTextPadding

            toastLabel.frame = CGRect(
                x: (keyWindow.bounds.width - width) / 2,
                y: keyWindow.bounds.height - keyWindow.safeAreaInsets.bottom - height - bottomMargin,
                width: width,
                height: height
            )

            keyWindow.addSubview(toastLabel)
            UIView.animate(withDuration: 0.3, animations: { toastLabel.alpha = 1.0 })

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                UIView.animate(withDuration: 0.3, animations: { toastLabel.alpha = 0.0 }) { _ in
                    toastLabel.removeFromSuperview()
                }
            }
        }
    }
}

