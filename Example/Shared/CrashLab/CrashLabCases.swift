//
//  CrashLabCases.swift
//  DemoApp
//
//  The Crash Lab's cases, read from `crash-lab/cases.json` (the same schema and ids as the
//  Android lab's), and the order the screens show them in.
//

import Foundation

struct CrashLabCase: Decodable, Identifiable {
    let id: String
    let section: String
    let title: String
    let expect: [String]?
    let steps: [String]?
    let status: String?
    let note: String?
    let requires: String?
    let trigger: String?

    /// Whether tapping it runs something: its trigger, its own or another case's, exists here and
    /// the case is not out of scope.
    var isRunnable: Bool {
        guard let trigger, status != "out_of_scope" else { return false }
        return CrashLabTriggers.ids.contains(trigger)
    }

    var detail: String {
        var lines: [String] = []
        if let status { lines.append("[\(status)]") }
        lines += (steps ?? []).map { "• \($0)" }
        lines += (expect ?? []).map { "✓ \($0)" }
        if let note { lines.append(note) }
        return lines.joined(separator: "\n")
    }
}

enum CrashLabCatalog {
    static let cases: [CrashLabCase] = {
        guard let url = Bundle.main.url(forResource: "cases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let cases = try? JSONDecoder().decode([CrashLabCase].self, from: data) else { return [] }
        return cases
    }()

    /// Sections in the order their first case appears.
    static var sections: [(name: String, cases: [CrashLabCase])] {
        var order: [String] = []
        var bySection: [String: [CrashLabCase]] = [:]
        for labCase in cases {
            if bySection[labCase.section] == nil { order.append(labCase.section) }
            bySection[labCase.section, default: []].append(labCase)
        }
        return order.map { ($0, bySection[$0] ?? []) }
    }

    /// Every case id, for the UI test that checks the screen lists the whole file.
    static var allIds: String { cases.map(\.id).joined(separator: ",") }
}
