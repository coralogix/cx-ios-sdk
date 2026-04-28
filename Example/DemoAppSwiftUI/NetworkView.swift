import SwiftUI

struct NetworkView: View {
    @State private var toastMessage: String?

    private struct Item {
        let title: String
        let subtitle: String
        let icon: String
        let action: () -> Void
    }

    private var items: [Item] {
        [
            Item(title: "Failing network request",
                 subtitle: "Simulate a client/server error",
                 icon: "xmark.octagon",
                 action: { NetworkSim.failureNetworkRequest() }),
            Item(title: "Successful network request",
                 subtitle: "Standard URLSession request",
                 icon: "checkmark.circle",
                 action: { NetworkSim.sendSuccesfullRequest() }),
            Item(title: "Flutter success request",
                 subtitle: "Simulate successful Flutter network",
                 icon: "bolt.horizontal.circle",
                 action: { NetworkSim.setNetworkRequestContextFlutterSuccsess() }),
            Item(title: "Flutter failure request",
                 subtitle: "Simulate failed Flutter network",
                 icon: "bolt.horizontal.circle.fill",
                 action: { NetworkSim.setNetworkRequestContextFailure() }),
            Item(title: "Alamofire success",
                 subtitle: "Successful Alamofire request",
                 icon: "bolt.circle",
                 action: { NetworkSim.succesfullAlamofire() }),
            Item(title: "Alamofire failure",
                 subtitle: "Failing Alamofire request",
                 icon: "bolt.slash",
                 action: { NetworkSim.failureAlamofire() }),
            Item(title: "Alamofire upload",
                 subtitle: "Upload a 2MB sample file",
                 icon: "arrow.up.doc",
                 action: {
                     let url = NetworkSim.createSampleFile(sizeInMB: 2)
                     NetworkSim.uploadFile(fileURL: url)
                 }),
            Item(title: "AFNetworking request",
                 subtitle: "Legacy AFNetworking example",
                 icon: "antenna.radiowaves.left.and.right",
                 action: { NetworkSim.sendAFNetworkingRequest() }),
            Item(title: "Download image (SDWebImage)",
                 subtitle: "Image download & caching",
                 icon: "photo.on.rectangle",
                 action: { NetworkSim.downloadImage() }),
            Item(title: "POST request",
                 subtitle: "Send JSON data to server",
                 icon: "arrow.up.circle",
                 action: { NetworkSim.performPostRequest() }),
            Item(title: "GET request",
                 subtitle: "Fetch data from server",
                 icon: "arrow.down.circle",
                 action: { NetworkSim.performGetRequest() }),
            Item(title: "Async/Await example",
                 subtitle: "async await in action",
                 icon: "arrow.triangle.2.circlepath",
                 action: { NetworkSim.callAsyncAwait() }),
            Item(title: "Async/Await with SSL Pinning",
                 subtitle: "async/await + custom delegate",
                 icon: "lock.shield",
                 action: { NetworkSim.callAsyncAwaitWithSSLPinning() }),
            Item(title: "Header & response body capture",
                 subtitle: "One POST showing all 4 fields: request_headers, response_headers, request_payload, response_payload",
                 icon: "list.bullet.rectangle",
                 action: { NetworkSim.sendRequestWithHeaderCapture() })
        ]
    }

    var body: some View {
        List {
            ForEach(items, id: \.title) { item in
                Button {
                    toastMessage = "Selected: \(item.title)"
                    item.action()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.body)
                                .foregroundColor(.primary)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: item.icon)
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 28)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Network instrumentation")
        .navigationBarTitleDisplayMode(.large)
        .trackCXView(name: "Network instrumentation")
        .toast(message: $toastMessage)
    }
}
