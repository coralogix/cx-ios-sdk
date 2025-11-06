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
