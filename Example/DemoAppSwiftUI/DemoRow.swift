import SwiftUI

struct DemoRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 28)
        }
        .padding(.vertical, 2)
    }
}
