//
//  CrashLabView.swift
//  DemoAppSwiftUI
//
//  The Crash Lab: launch settings (applied at the next launch) and every case of
//  `crash-lab/cases.json`, each with what to check and, when it has one, its trigger. Mirrors
//  `CrashLabViewController` in the UIKit demo app; both run the shared `CrashLabTriggers`.
//

import SwiftUI

struct CrashLabView: View {
    private let settings = CrashLabSettings.shared
    private let sections = CrashLabCatalog.sections
    /// Bumped on every settings change, so the rows re-read the file.
    @State private var revision = 0
    @State private var message: String?

    var body: some View {
        List {
            Text("\(CrashLabCatalog.cases.count) cases · settings apply at the next launch")
                .font(.footnote)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("crashLab.caseIds")
                .accessibilityValue(CrashLabCatalog.allIds)

            Section(header: Text("Launch settings")) {
                Button("Reset every setting") {
                    settings.reset()
                    revision += 1
                }
                .foregroundColor(.red)
                .accessibilityIdentifier("crashLab.reset")
                ForEach(CrashLabSetting.allCases, id: \.self) { setting in
                    let value = settings[setting].description
                    Button {
                        settings.cycle(setting)
                        revision += 1
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(setting.label).foregroundColor(.primary)
                            Text(value).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .accessibilityIdentifier("crashLab.setting.\(setting.key)")
                    .accessibilityValue(value)
                }
            }
            .id(revision)

            ForEach(sections, id: \.name) { section in
                Section(header: Text(section.name)) {
                    ForEach(section.cases) { labCase in
                        Button {
                            guard labCase.isRunnable, let trigger = labCase.trigger else { return }
                            message = CrashLabTriggers.run(trigger)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(labCase.id) · \(labCase.title)").foregroundColor(.primary)
                                Text(labCase.detail).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .disabled(!labCase.isRunnable)
                        .accessibilityIdentifier("crashLab.case.\(labCase.id)")
                    }
                }
            }
        }
        .navigationTitle("Crash Lab")
        .alert(isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Alert(title: Text("Crash Lab"), message: Text(message ?? ""), dismissButton: .default(Text("OK")))
        }
    }
}
