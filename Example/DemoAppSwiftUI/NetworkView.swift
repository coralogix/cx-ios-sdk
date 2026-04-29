import SwiftUI

struct NetworkView: View {
    var body: some View {
        ActionListView(
            title: "Network instrumentation",
            cxViewName: "Network instrumentation",
            items: [
                ActionItem(title: "Failing network request",
                           subtitle: "Simulate a client/server error",
                           icon: "xmark.octagon",
                           action: { NetworkSim.failureNetworkRequest() }),
                ActionItem(title: "Successful network request",
                           subtitle: "Standard URLSession request",
                           icon: "checkmark.circle",
                           action: { NetworkSim.sendSuccesfullRequest() }),
                ActionItem(title: "Flutter success request",
                           subtitle: "Simulate successful Flutter network",
                           icon: "bolt.horizontal.circle",
                           action: { NetworkSim.setNetworkRequestContextFlutterSuccsess() }),
                ActionItem(title: "Flutter failure request",
                           subtitle: "Simulate failed Flutter network",
                           icon: "bolt.horizontal.circle.fill",
                           action: { NetworkSim.setNetworkRequestContextFailure() }),
                ActionItem(title: "Alamofire success",
                           subtitle: "Successful Alamofire request",
                           icon: "bolt.circle",
                           action: { NetworkSim.succesfullAlamofire() }),
                ActionItem(title: "Alamofire failure",
                           subtitle: "Failing Alamofire request",
                           icon: "bolt.slash",
                           action: { NetworkSim.failureAlamofire() }),
                ActionItem(title: "Alamofire upload",
                           subtitle: "Upload a 2MB sample file",
                           icon: "arrow.up.doc",
                           action: {
                               let url = NetworkSim.createSampleFile(sizeInMB: 2)
                               NetworkSim.uploadFile(fileURL: url)
                           }),
                ActionItem(title: "AFNetworking request",
                           subtitle: "Legacy AFNetworking example",
                           icon: "antenna.radiowaves.left.and.right",
                           action: { NetworkSim.sendAFNetworkingRequest() }),
                ActionItem(title: "Download image (SDWebImage)",
                           subtitle: "Image download & caching",
                           icon: "photo.on.rectangle",
                           action: { NetworkSim.downloadImage() }),
                ActionItem(title: "POST request",
                           subtitle: "Send JSON data to server",
                           icon: "arrow.up.circle",
                           action: { NetworkSim.performPostRequest() }),
                ActionItem(title: "GET request",
                           subtitle: "Fetch data from server",
                           icon: "arrow.down.circle",
                           action: { NetworkSim.performGetRequest() }),
                ActionItem(title: "Async/Await example",
                           subtitle: "async await in action",
                           icon: "arrow.triangle.2.circlepath",
                           action: { NetworkSim.callAsyncAwait() }),
                ActionItem(title: "Async/Await with SSL Pinning",
                           subtitle: "async/await + custom delegate",
                           icon: "lock.shield",
                           action: { NetworkSim.callAsyncAwaitWithSSLPinning() }),
                ActionItem(title: "Header & response body capture",
                           subtitle: "One POST showing all 4 fields: request_headers, response_headers, request_payload, response_payload",
                           icon: "list.bullet.rectangle",
                           action: { NetworkSim.sendRequestWithHeaderCapture() })
            ]
        )
    }
}
