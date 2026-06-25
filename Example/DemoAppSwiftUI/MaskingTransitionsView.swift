import SwiftUI
import Coralogix
import SessionReplay

// Reproduces the customer-reported Session Replay masking gap: text left
// un-masked while a bottom sheet is presented and during the back-navigation
// ("back move") transition. SwiftUI content is masked through the Vision-OCR
// pipeline — the same path the SDK uses for Flutter — so this screen is the
// closest native analog of the customer's Flutter app.
//
// To exercise it: launch with `--mask-all-text` (records with maskText [".*"]),
// open this screen, then (1) present the bottom sheet and (2) push the detail
// screen and swipe back. Pull the saved frames from the simulator's
// Documents/sessionreplay folder and look for text that escaped masking.
struct MaskingTransitionsView: View {
    @State private var showSheet = false

    struct Customer: Identifiable {
        let id = UUID()
        let icon: String
        let name: String
        let email: String
        let card: String
    }

    static let customers: [Customer] = [
        .init(icon: "person.crop.circle.fill", name: "Olivia Bennett", email: "olivia.bennett@example.com", card: "4539 8842 1190 5567"),
        .init(icon: "person.crop.circle.fill", name: "Liam Carter", email: "liam.carter@example.com", card: "5221 7741 0098 2231"),
        .init(icon: "person.crop.circle.fill", name: "Sofia Rossi", email: "sofia.rossi@example.com", card: "6011 3387 4452 1009"),
        .init(icon: "person.crop.circle.fill", name: "Noah Schmidt", email: "noah.schmidt@example.com", card: "4024 0071 5523 8890"),
        .init(icon: "person.crop.circle.fill", name: "Emma Dubois", email: "emma.dubois@example.com", card: "3782 822463 10005"),
        .init(icon: "person.crop.circle.fill", name: "Kenji Tanaka", email: "kenji.tanaka@example.com", card: "4716 9921 7745 3320"),
        .init(icon: "person.crop.circle.fill", name: "Aisha Khan", email: "aisha.khan@example.com", card: "5412 7556 1187 4432"),
        .init(icon: "person.crop.circle.fill", name: "Lucas Silva", email: "lucas.silva@example.com", card: "6011 5523 8841 9090"),
        .init(icon: "person.crop.circle.fill", name: "Mia Andersen", email: "mia.andersen@example.com", card: "4485 2299 0071 6654"),
        .init(icon: "person.crop.circle.fill", name: "Daniel Cohen", email: "daniel.cohen@example.com", card: "5105 1051 0510 5100"),
        .init(icon: "person.crop.circle.fill", name: "Chloe Martin", email: "chloe.martin@example.com", card: "4111 1111 1111 1111"),
        .init(icon: "person.crop.circle.fill", name: "Hiroshi Sato", email: "hiroshi.sato@example.com", card: "3530 1113 3330 0000"),
        .init(icon: "person.crop.circle.fill", name: "Isabella Costa", email: "isabella.costa@example.com", card: "6011 0009 9013 9424"),
        .init(icon: "person.crop.circle.fill", name: "Ethan Wright", email: "ethan.wright@example.com", card: "4012 8888 8888 1881"),
        .init(icon: "person.crop.circle.fill", name: "Yara Haddad", email: "yara.haddad@example.com", card: "5555 5555 5555 4444")
    ]

    var body: some View {
        List {
            Section {
                Text("Record with Session Replay (launch arg --mask-all-text). " +
                     "Present the bottom sheet and swipe back from the detail screen, " +
                     "then inspect the saved frames for un-masked text.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section("Transitions") {
                Button {
                    showSheet = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Present Bottom Sheet").foregroundColor(.primary)
                            Text("Sensitive text over the list").font(.caption).foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "rectangle.bottomthird.inset.filled").frame(width: 28)
                    }
                }

                NavigationLink {
                    MaskingTransitionsDetailView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Push Detail Screen").foregroundColor(.primary)
                            Text("Swipe back to test the back transition").font(.caption).foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "chevron.right.circle").frame(width: 28)
                    }
                }
            }

            Section("Customer Records") {
                ForEach(Self.customers) { customer in
                    customerRow(customer)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Masking Transitions")
        .navigationBarTitleDisplayMode(.inline)
        .trackCXView(name: "Masking Transitions")
        .sheet(isPresented: $showSheet) {
            MaskingTransitionsSheetView()
        }
    }

    private func customerRow(_ customer: Customer) -> some View {
        HStack(spacing: 12) {
            Image(systemName: customer.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(customer.name).font(.body)
                Text(customer.email).font(.caption).foregroundColor(.secondary)
                Text(customer.card).font(.system(.footnote, design: .monospaced))
            }
        }
        .padding(.vertical, 4)
    }
}

// Bottom sheet with sensitive text. With detents it sits as a true bottom
// sheet over the list, recreating the customer's "bottom sheet" scenario.
struct MaskingTransitionsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cardNumber = "4539 8842 1190 5567"

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                sheetBody.presentationDetents([.medium, .large])
            } else {
                sheetBody
            }
        }
    }

    private var sheetBody: some View {
        NavigationView {
            List {
                Section("Payment Details") {
                    labeledRow("Cardholder", "Olivia Bennett")
                    HStack {
                        Text("Card Number")
                        Spacer()
                        TextField("0000 0000 0000 0000", text: $cardNumber)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 200)
                    }
                    labeledRow("Expiry", "08 / 27")
                    labeledRow("CVV", "123")
                }
                Section("Billing Address") {
                    labeledRow("Street", "42 Riverside Lane")
                    labeledRow("City", "Manchester")
                    labeledRow("Postcode", "M1 4AB")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .trackCXView(name: "Masking Transitions Sheet")
    }

    private func labeledRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

// Detail screen pushed onto the stack so the interactive swipe-back ("back
// move") can be performed while sensitive text is on screen.
struct MaskingTransitionsDetailView: View {
    var body: some View {
        List {
            Section {
                Text("Swipe from the left edge to pop this screen. A frame captured " +
                     "mid-transition is the one to inspect for un-masked text.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Section("Account") {
                detailRow("Full Name", "Olivia Bennett")
                detailRow("Email", "olivia.bennett@example.com")
                detailRow("Phone", "+44 7700 900123")
                detailRow("National ID", "QQ 12 34 56 C")
                detailRow("IBAN", "GB29 NWBK 6016 1331 9268 19")
                detailRow("Card", "4539 8842 1190 5567")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Account Detail")
        .navigationBarTitleDisplayMode(.inline)
        .trackCXView(name: "Masking Transitions Detail")
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced))
        }
    }
}
