// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Coralogix",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "Coralogix", type: .dynamic, targets: ["Coralogix"])
    ],
    dependencies: [
    ],
    targets: [
        .binaryTarget(
            name: "CrashReporter",
            path:"Coralogix/Frameworks/PLCrashReporter/CrashReporter.xcframework"
        ),
        .binaryTarget(
            name: "OpenTelemetryApi",
            path:"Coralogix/Frameworks/OpenTelemetryApi.xcframework"
        ),
        .binaryTarget(
            name: "OpenTelemetrySdk",
            path:"Coralogix/Frameworks/OpenTelemetrySdk.xcframework"
        ),
        .target(
            name: "Coralogix",
            dependencies: [
                .target(name: "OpenTelemetryApi"),
                .target(name: "OpenTelemetrySdk"),
                .target(name: "CrashReporter"),
            ],
            path: "Coralogix/Sources/",
            resources: [
                .copy("OpenTelemetryApi.xcframework"),
                .copy("OpenTelemetrySDK.xcframework"),
                .copy("CrashReporter.xcframework")
            ]
        ),
        .testTarget(
            name: "CoralogixRumTests",
            dependencies: ["Coralogix"],
            path: "Coralogix/Tests/")
    ]
)
