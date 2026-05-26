//
//  EventPipelineTests.swift
//
//
//  Created by Coralogix DEV TEAM on 26/05/2026.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class EventPipelineTests: XCTestCase {

    // MARK: - fixtures

    private struct LabelEvent: TelemetryEvent {
        let id: UUID = UUID()
        let timestamp: Date = Date()
        var type: EventType { .error }
        let label: String

        func toOTelAttributes() -> [String: AttributeValue] { [:] }
    }

    private struct AppendMiddleware: EventMiddleware {
        let marker: String
        func process(_ event: TelemetryEvent) -> TelemetryEvent? {
            guard let labelEvent = event as? LabelEvent else { return event }
            return LabelEvent(label: labelEvent.label + marker)
        }
    }

    private struct DroppingMiddleware: EventMiddleware {
        func process(_ event: TelemetryEvent) -> TelemetryEvent? { nil }
    }

    private final class SpyMiddleware: EventMiddleware {
        var seenLabels: [String] = []
        func process(_ event: TelemetryEvent) -> TelemetryEvent? {
            if let labelEvent = event as? LabelEvent {
                seenLabels.append(labelEvent.label)
            }
            return event
        }
    }

    // MARK: - empty / passthrough

    func testEmptyPipelineReturnsEventUnchanged() {
        let pipeline = EventPipeline()
        let event = LabelEvent(label: "x")

        let result = pipeline.process(event)

        XCTAssertEqual((result as? LabelEvent)?.label, "x")
    }

    // MARK: - ordering & mutation propagation

    func testMiddlewaresRunInInsertionOrder() {
        let pipeline = EventPipeline()
        pipeline.add(AppendMiddleware(marker: "A"))
        pipeline.add(AppendMiddleware(marker: "B"))
        pipeline.add(AppendMiddleware(marker: "C"))

        let result = pipeline.process(LabelEvent(label: "start:"))

        XCTAssertEqual((result as? LabelEvent)?.label, "start:ABC")
    }

    func testEachMiddlewareSeesPreviousMiddlewaresOutput() {
        let pipeline = EventPipeline()
        pipeline.add(AppendMiddleware(marker: "1"))
        let spy = SpyMiddleware()
        pipeline.add(spy)
        pipeline.add(AppendMiddleware(marker: "2"))

        _ = pipeline.process(LabelEvent(label: "input"))

        XCTAssertEqual(spy.seenLabels, ["input1"])
    }

    // MARK: - short-circuit

    func testReturningNilShortCircuitsPipeline() {
        let pipeline = EventPipeline()
        pipeline.add(AppendMiddleware(marker: "A"))
        pipeline.add(DroppingMiddleware())
        let afterDrop = SpyMiddleware()
        pipeline.add(afterDrop)

        let result = pipeline.process(LabelEvent(label: "start:"))

        XCTAssertNil(result)
        XCTAssertEqual(afterDrop.seenLabels, [], "middleware after a dropping stage must not be invoked")
    }

    func testFirstMiddlewareDroppingShortCircuitsImmediately() {
        let pipeline = EventPipeline()
        pipeline.add(DroppingMiddleware())
        let spy = SpyMiddleware()
        pipeline.add(spy)

        let result = pipeline.process(LabelEvent(label: "x"))

        XCTAssertNil(result)
        XCTAssertEqual(spy.seenLabels, [])
    }
}
