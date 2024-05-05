// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CoralogixRum",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "CoralogixRum",
            targets: ["CoralogixRum"])
    ],
    dependencies: [
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift", from: "1.9.1"),
        .package(url: "https://github.com/microsoft/plcrashreporter", from: "1.11.1")
    ],
    targets: [
        .target(
            name: "CoralogixRum",
            dependencies: [
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift"),
                .product(name: "OTLPHTTPExporter", package: "opentelemetry-swift"),
                .product(name: "StdoutExporter", package: "opentelemetry-swift"),
                .product(name: "URLSessionInstrumentation", package: "opentelemetry-swift"),
                .product(name: "ResourceExtension", package: "opentelemetry-swift"),
                .product(name: "OpenTelemetryProtocolExporter", package: "opentelemetry-swift"),
                .product(name: "SignPostIntegration", package: "opentelemetry-swift"),
                .product(name: "CrashReporter", package: "PLCrashReporter")
            ],
            path: "CoralogixRum/Sources/"),
        .testTarget(
            name: "CoralogixRumTests",
            dependencies: ["CoralogixRum"])
    ]
)
