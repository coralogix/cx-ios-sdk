// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Coralogix",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(name: "Coralogix", targets: ["Coralogix"]),
        .library(name: "CoralogixInternal", targets: ["CoralogixInternal"]),
        .library(name: "SessionReplay", targets: ["SessionReplay"])
    ],
    targets: [
        .binaryTarget(
            name: "CrashReporter",
            path:"Coralogix/Frameworks/PLCrashReporter/CrashReporter.xcframework"
        ),
        .target(
            name: "CoralogixInternal",
            path: "CoralogixInternal/Sources/",
        ),
        .target(
            name: "Coralogix",
            dependencies: [
                .target(name: "CoralogixInternal"),
                .target(name: "CrashReporter")
            ],
            path: "Coralogix/Sources/"
        ),
        .target(
            name: "SessionReplay",
            dependencies: [
                .target(name: "CoralogixInternal"),
            ],
            path: "SessionReplay/Sources/"
        ),
        .testTarget(
            name: "CoralogixRumTests",
            dependencies: ["Coralogix"],
            path: "Tests/CoralogixRumTests/"
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
