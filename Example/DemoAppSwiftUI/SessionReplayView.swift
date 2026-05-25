import SwiftUI
import Coralogix
import SessionReplay

struct SessionReplayView: View {
    @State private var toastMessage: String?
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var creditCardText = ""

    // Stress content for the SR text-masking pipeline: multi-language paragraphs
    // (RTL + CJK) and short non-word tokens that the old en-US + language-corrected
    // VNRecognizeTextRequest used to silently drop. Scroll through this section to
    // exercise the widened TextScanner config under maskAllTexts.
    private static let stressTextLines: [String] = [
        "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs — abc123 OK.",
        "El veloz murciélago hindú comía feliz cardillo y kiwi. La cigüeña tocaba el saxofón detrás del palenque.",
        "Portez ce vieux whisky au juge blond qui fume. Voix ambiguë d'un cœur qui préfère les jattes de kiwis.",
        "Zwölf Boxkämpfer jagen Viktor quer über den großen Sylter Deich — Größe ÄÖÜ.",
        "Ma la volpe, col suo balzo, ha raggiunto il quieto Fido — perché sì.",
        "Um pequeno jabuti xereta viu dez cegonhas felizes — coração à beça.",
        "Съешь же ещё этих мягких французских булок, да выпей чаю.",
        "דג סקרן שט לו בים זך אך לפתע פגש חבורה נחמדה של דגים.",
        "نص حكيم له سر قاطع وذو شأن عظيم مكتوب على ثوب أخضر ومغلف بجلد أزرق.",
        "いろはにほへと ちりぬるを — 価格 ¥1,200 OK 確認。",
        "敏捷的棕色狐狸跳过懒狗。今天 ¥99.90 限时特惠 OK。",
        "다람쥐 헌 쳇바퀴에 타고파. 확인 ₩9,900 OK.",
        "เป็นมนุษย์สุดประเสริฐเลิศคุณค่า กว่าบรรดาฝูงสัตว์เดรัจฉาน — OK.",
        "Ξεσκεπάζω τὴν ψυχοφθόρα βδελυγμία — Τιμή €4,99.",
        "OK · USB-C · v2.6.3 · ETA 5m · ID#A1B2 · PIN 0000",
        "$4.99 · €19,90 · £10.50 · ¥1,200 · ₪59.90 · ₹499 · ₩9,900",
        "HTTP/2 · TLS 1.3 · SHA-256 · 200 OK · 404 · 500 · 422",
        "A1B2-C3D4 · P/N: X-42 · MAC 00:1A:2B:3C:4D:5E · UUID e4f1…"
    ]

    var body: some View {
        List {
            Section {
                Text("Quick controls for Session Replay recording, masking and events.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section {
                actionRow(icon: "record.circle", title: "Start Recording",
                          subtitle: "Begin capturing user interactions for this session.") {
                    CoralogixRumManager.shared.sdk.startRecording()
                    toastMessage = "Recording started"
                }

                actionRow(icon: "stop.circle", title: "Stop Recording",
                          subtitle: "Stop recording and finalize the current session.") {
                    CoralogixRumManager.shared.sdk.stopRecording()
                    toastMessage = "Recording stopped"
                }

                actionRow(icon: "sparkles", title: "Capture Event",
                          subtitle: "Manually send a custom event to Session Replay.") {
                    CoralogixRumManager.shared.sdk.captureEvent()
                    toastMessage = "Event captured"
                }

                actionRow(icon: "waveform.circle", title: "Is Recording?",
                          subtitle: "Check if Session Replay is currently recording.") {
                    alertMessage = "isRecording: \(CoralogixRumManager.shared.sdk.isSRRecording())"
                    showAlert = true
                }

                actionRow(icon: "checkmark.seal", title: "Is Initialized?",
                          subtitle: "Check if the SDK has been initialized.") {
                    alertMessage = "isInitialized: \(CoralogixRumManager.shared.sdk.isSRInitialized())"
                    showAlert = true
                }

                actionRow(icon: "arrow.triangle.2.circlepath", title: "Update Session ID",
                          subtitle: "Generate and apply a fresh session identifier.") {
                    CoralogixRumManager.shared.sdk.update(sessionId: UUID().uuidString.lowercased())
                    toastMessage = "Session ID updated"
                }

            }

            Section("Credit Card Input") {
                HStack {
                    Text("Card Number")
                        .font(.body)
                    Spacer()
                    TextField("0000 0000 0000 0000", text: $creditCardText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 200)
                }
                .cxMask()
            }

            Section("Sample Images") {
                ForEach(["creditcard.fill", "person.crop.rectangle", "photo.fill", "cart.fill", "star.fill"], id: \.self) { icon in
                    HStack {
                        Spacer()
                        Image(systemName: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 80)
                            .foregroundColor(.accentColor)
                        Spacer()
                    }
                    .frame(height: 150)
                }
            }

            Section("Stress Test — Mixed Text") {
                ForEach(Self.stressTextLines, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Session Replay")
        .navigationBarTitleDisplayMode(.inline)
        .trackCXView(name: "Session Replay")
        .alert("Alert", isPresented: $showAlert, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(alertMessage ?? "")
        })
        .toast(message: $toastMessage)
    }

    private func actionRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 28)
            }
            .padding(.vertical, 2)
        }
    }
}
