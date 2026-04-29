import SwiftUI
import Coralogix
import SessionReplay

struct SessionReplayView: View {
    @State private var toastMessage: String?
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var creditCardText = ""

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

                actionRow(icon: "eye.slash", title: "Register Mask Region",
                          subtitle: "Mask a region of the screen from recording.") {
                    let id = "demoMaskRegion"
                    CoralogixRumManager.shared.sdk.registerMaskRegion(id)
                    alertMessage = "Registered mask region with id: \(id)"
                    showAlert = true
                }

                actionRow(icon: "eye", title: "Unregister Mask Region",
                          subtitle: "Remove the mask from the demo region.") {
                    let id = "demoMaskRegion"
                    CoralogixRumManager.shared.sdk.unregisterMaskRegion(id)
                    alertMessage = "Unregistered mask region with id: \(id)"
                    showAlert = true
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
