import SwiftUI

struct ClockView: View {
    @State private var timeString = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            Spacer()
            Text(timeString)
                .font(.system(size: 40, weight: .medium, design: .monospaced))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle("Clock")
        .navigationBarTitleDisplayMode(.inline)
        .trackCXView(name: "Clock")
        .onAppear { updateTime() }
        .onReceive(timer) { _ in updateTime() }
    }

    private func updateTime() {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        timeString = formatter.string(from: Date())
    }
}
