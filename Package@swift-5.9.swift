// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Coralogix",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(name: "Coralogix", type: .dynamic, targets: ["Coralogix"])
    ],
    dependencies: [
        //.package(url: "https://github.com/open-telemetry/opentelemetry-swift", from: "1.9.2"),
    ],
    targets: [
        .binaryTarget(
            name: "CrashReporter",
            path:"Coralogix/Frameworks/PLCrashReporter/CrashReporter.xcframework"
        ),
        .target(
            name: "Coralogix",
            dependencies: [
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
