import SwiftUI
import Coralogix

struct ActionListView: View {
    let title: String
    let cxViewName: String
    let items: [ActionItem]
    var titleDisplayMode: NavigationBarItem.TitleDisplayMode = .large

    @State private var toastMessage: String?

    var body: some View {
        List {
            ForEach(items, id: \.title) { item in
                Button {
                    toastMessage = "Selected: \(item.title)"
                    item.action()
                } label: {
                    DemoRow(icon: item.icon, title: item.title, subtitle: item.subtitle)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(titleDisplayMode)
        .trackCXView(name: cxViewName)
        .toast(message: $toastMessage)
    }
}
