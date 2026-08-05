//
//  MaskDemoView.swift
//  DemoAppSwift
//
//  Created by Tomer Har Yoffi on 05/11/2025.
//

import SwiftUI

struct MaskDemoView: View {
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var textViewText: String = "Enter some text here..."
    @State private var sliderValue: Double = 50
    @State private var stepperValue: Double = 5
    @State private var toggleOn: Bool = true
    @State private var selectedSegment: Int = 0
    @State private var progressValue: Float = 0.4
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                
                // Title
                Text("Mask Demo Page")
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                    .cxMask() // masked example
                
                // Description
                Text("This screen contains common SwiftUI components.\nYou can toggle cxMask on any of them.")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .cxMask() // masked example
                
                // Username Field
                TextField("Username", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .cxMask() // masked example
                
                // Password Field
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .cxMask() // masked example
                
                // TextView equivalent
                TextEditor(text: $textViewText)
                    .frame(height: 100)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                    )
                
                // Masked Label
                Text("Sensitive Info")
                    .foregroundColor(.red)
                    .cxMask() // masked example

                // Keypads — mirrors the UIKit demo's masked/unmasked pair.
                //
                // `.cxMask()` overlays a masked UIView on top of this container, so the replay
                // blacks the keypad out and draws no tap marker over it. Unlike the UIKit
                // `cxMask`, the overlay is not an ancestor of the keys, so their interaction
                // events still report the digit. Masking a SwiftUI control's interaction text is
                // not supported yet — see the SessionReplay README.
                Text("Keypads: the left one is masked at the container. "
                     + "Tap both and compare them in the replay.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                HStack(spacing: 16) {
                    // One shared identifier on the masked pad: `element_id` comes from
                    // accessibilityIdentifier and is not redacted, so per-digit identifiers would
                    // leak the sequence the masking is meant to hide.
                    KeypadView(tint: .red) { _ in "masked_keypad_key" }
                        .cxMask() // 👈 masks the whole container, keys included
                    KeypadView(tint: .blue) { "keypad_key_\($0)" }
                }

                // Button
                Button(action: {}) {
                    Text("Submit")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .cxMask() // masked example
                
                // Toggle
                Toggle("Enable Feature", isOn: $toggleOn)
                    .padding(.horizontal)
                    .cxMask() // masked example
                
                // Slider
                VStack {
                    Text("Slider Value: \(Int(sliderValue))")
                    Slider(value: $sliderValue, in: 0...100)
                        .cxMask() // masked example
                }
                
                // Segmented Control
                Picker("Options", selection: $selectedSegment) {
                    Text("One").tag(0)
                    Text("Two").tag(1)
                    Text("Three").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                
                // Stepper
                Stepper("Value: \(Int(stepperValue))", value: $stepperValue, in: 0...10)
                    .cxMask() // masked example
                
                // Progress View
                VStack {
                    ProgressView(value: progressValue)
                    Button("Increase Progress") {
                        progressValue = min(progressValue + 0.1, 1.0)
                    }
                }
                .cxMask() // masked example
                
                // Image
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.teal)
                    .clipShape(Circle())
                    .cxMask() // masked example
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
    }
}

/// A 3×2 grid of individually tappable keys — the shape that made masking-by-container matter:
/// hit-testing resolves a single key, not the container the mask was applied to.
struct KeypadView: View {
    let tint: Color
    let identifierForDigit: (Int) -> String

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { column in
                        let digit = row * 3 + column + 1
                        Button(action: {}) {
                            Text("\(digit)")
                                .font(.system(size: 20, weight: .bold))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .foregroundColor(tint)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(tint.opacity(0.4), lineWidth: 1)
                        )
                        .accessibilityIdentifier(identifierForDigit(digit))
                    }
                }
            }
        }
        .frame(height: 92)
    }
}
