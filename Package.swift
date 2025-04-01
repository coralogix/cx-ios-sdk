// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Coralogix",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(name: "Coralogix", targets: ["Coralogix"])
    ],
    dependencies: [
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift", from: "1.14.0"),
    ],
    targets: [
        .binaryTarget(
            name: "CrashReporter",
            path:"Coralogix/Frameworks/PLCrashReporter/CrashReporter.xcframework"
        ),
        .target(
            name: "Coralogix",
            dependencies: [.product(name: "OpenTelemetryApi", package: "opentelemetry-swift"),
                           .product(name: "OpenTelemetrySDK", package: "opentelemetry-swift"),
                           .target(name: "CrashReporter"),
            ],
            path: "Coralogix/Sources/"
        ),
        .testTarget(
            name: "CoralogixRumTests",
            dependencies: ["Coralogix"],
            path: "Coralogix/Tests/")
    ]
)
