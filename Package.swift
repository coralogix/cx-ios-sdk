// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Coralogix",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(name: "Coralogix", targets: ["Coralogix"]),
        .library(name: "CoralogixInternal", targets: ["CoralogixInternal"]),
        .library(name: "SessionReplay", targets: ["SessionReplay"])
    ],
    dependencies: [
        .package(url: "https://github.com/microsoft/plcrashreporter", exact: "1.11.1")
    ],
    targets: [
        .target(
            name: "CoralogixInternal",
            path: "CoralogixInternal/Sources/"
        ),
        .target(
            name: "Coralogix",
            dependencies: [
                .target(name: "CoralogixInternal"),
                .product(name: "CrashReporter", package: "plcrashreporter")
            ],
            path: "Coralogix/Sources/"
        ),
        .target(
            name: "SessionReplay",
            dependencies: [
                .target(name: "CoralogixInternal")
            ],
            path: "SessionReplay/Sources/"
        ),
        .testTarget(
            name: "CoralogixRumTests",
            dependencies: ["Coralogix"],
            path: "Tests/CoralogixRumTests/"
        ),
        .testTarget(
            name: "CoralogixInternalTests",
            dependencies: ["CoralogixInternal"],
            path: "Tests/CoralogixInternalTests/"
        ),
        .testTarget(
            name: "SessionReplayTests",
            dependencies: ["SessionReplay"],
            path: "Tests/SessionReplayTests",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
