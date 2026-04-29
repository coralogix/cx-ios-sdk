import SwiftUI

struct UserActionsView: View {
    @State private var toastMessage: String?
    @State private var showModal = false
    @State private var showAlert = false
    @State private var showCrashBadAccessConfirm = false
    @State private var showCrashFatalConfirm = false

    var body: some View {
        List {
            Section("Swipe Demo") {
                VStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .trackCXSwipeAction()
                    Text("Swipe the icon to emit a RUM swipe span")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)
                }
            }

            Section {
                Button("Log In (resolveTargetName demo)") {
                    toastMessage = "Login tapped — target_element will be 'Login Button' in RUM"
                }
                .accessibilityIdentifier("loginButton")
                .trackCXTapAction(name: "Log In")
            }

            Section {
                Button {
                    showModal = true
                } label: {
                    DemoRow(icon: "rectangle.on.rectangle", title: "Modal Presentation",
                            subtitle: "Track full-screen modals and presentation flows")
                }
                .trackCXTapAction(name: "Modal Presentation")

                NavigationLink(destination: SegmentedGridView()) {
                    DemoRow(icon: "square.grid.2x2", title: "Segmented Collection",
                            subtitle: "Monitor segmented controls & collection interactions")
                }

                NavigationLink(destination: PageCarouselView()) {
                    DemoRow(icon: "rectangle.portrait.on.rectangle.portrait", title: "Page Controller",
                            subtitle: "Capture page swipes and transitions")
                }

                Button {
                    showAlert = true
                } label: {
                    DemoRow(icon: "exclamationmark.triangle", title: "Alert View",
                            subtitle: "Instrument alerts and user confirmations")
                }
                .trackCXTapAction(name: "Alert View")

                Button {
                    toastMessage = "Tapped — but text is suppressed in RUM (shouldSendText → false)"
                } label: {
                    DemoRow(icon: "eye.slash", title: "Sensitive Label (text suppressed)",
                            subtitle: "Tap this — shouldSendText returns false, so no text is captured in RUM")
                }
                .accessibilityIdentifier("sensitiveLabel")

                Button {
                    showCrashBadAccessConfirm = true
                } label: {
                    DemoRow(icon: "xmark.octagon.fill", title: "Simulate Crash: Bad Access",
                            subtitle: "Trigger an EXC_BAD_ACCESS crash for testing")
                }

                Button {
                    showCrashFatalConfirm = true
                } label: {
                    DemoRow(icon: "xmark.octagon", title: "Simulate Crash: Fatal Error",
                            subtitle: "Trigger a fatalError() crash for testing")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("User Actions")
        .navigationBarTitleDisplayMode(.large)
        .trackCXView(name: "User Actions")
        .sheet(isPresented: $showModal) {
            SimpleModalView()
        }
        .alert("Alert", isPresented: $showAlert) {
            Button("OK") { toastMessage = "Alert dismissed" }
        } message: {
            Text("I'm an alert")
        }
        .alert("⚠️ Simulate Crash", isPresented: $showCrashBadAccessConfirm) {
            Button("Cancel", role: .cancel) { toastMessage = "Crash cancelled" }
            Button("Crash Now", role: .destructive) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    triggerBadAccessCrash()
                }
            }
        } message: {
            Text("This will crash the app to test crash reporting. Continue?")
        }
        .alert("⚠️ Simulate Fatal Error Crash", isPresented: $showCrashFatalConfirm) {
            Button("Cancel", role: .cancel) { toastMessage = "Crash cancelled" }
            Button("Crash Now", role: .destructive) {
                fatalError("Simulated crash (fatalError)")
            }
        } message: {
            Text("This will crash the app using fatalError(). Continue?")
        }
        .toast(message: $toastMessage)
    }

    private func triggerBadAccessCrash() {
        let pointer = UnsafeMutablePointer<Int>(bitPattern: 0x16)!
        pointer.pointee = 42
    }
}

struct SimpleModalView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text("Modal View")
                .font(.title2)
                .fontWeight(.semibold)
            Text("This modal was presented full-screen.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Dismiss") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .trackCXView(name: "Modal View")
    }
}

struct SegmentedGridView: View {
    @State private var selectedSegment = 0

    private let segments = ["Animals", "Plants", "Objects"]
    private let data: [[String]] = [
        ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮"],
        ["🌱", "🌿", "🍀", "🌺", "🌸", "🌼", "🌻", "🌹", "🌷", "🍁", "🍂", "🎋"],
        ["⚽️", "🏀", "🏈", "⚾️", "🎾", "🏐", "🏉", "🎱", "🏓", "🏸", "🥊", "🎯"]
    ]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Category", selection: $selectedSegment) {
                ForEach(0..<segments.count, id: \.self) { i in
                    Text(segments[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                    ForEach(data[selectedSegment], id: \.self) { item in
                        Text(item)
                            .font(.largeTitle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Segmented Collection")
        .navigationBarTitleDisplayMode(.inline)
        .trackCXView(name: "Segmented Collection")
    }
}

struct PageCarouselView: View {
    @State private var currentPage = 0

    private let pages: [(title: String, subtitle: String, icon: String, color: Color)] = [
        ("Overview", "Total sessions & key metrics for your app", "chart.bar.fill", .indigo),
        ("Sessions", "Recent user sessions and replay data", "person.2.fill", .teal),
        ("Performance", "FPS, CPU & memory vitals", "gauge.medium", .orange)
    ]

    var body: some View {
        TabView(selection: $currentPage) {
            ForEach(0..<pages.count, id: \.self) { index in
                let page = pages[index]
                ZStack {
                    LinearGradient(
                        colors: [page.color.opacity(0.8), page.color.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 16) {
                        Image(systemName: page.icon)
                            .font(.system(size: 56, weight: .medium))
                            .foregroundColor(.white)
                        Text(page.title)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text(page.subtitle)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
                .cornerRadius(20)
                .padding(.horizontal, 24)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page())
        .navigationTitle("Page Controller")
        .navigationBarTitleDisplayMode(.inline)
        .trackCXView(name: "Page Controller")
    }
}
