import Foundation

struct ActionItem {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void
}
