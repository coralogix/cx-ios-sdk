// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Coralogix",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(name: "Coralogix", type: .dynamic, targets: ["Coralogix"]),
        .library(name: "Coralogix-Internal", targets: ["Coralogix-Internal"])
    ],
    targets: [
        .binaryTarget(
            name: "CrashReporter",
            path:"Coralogix/Frameworks/PLCrashReporter/CrashReporter.xcframework"
        ),
        .target(
            name: "Coralogix-Internal",
            path: "Coralogix-Internal/Sources/"
        ),
        .target(
            name: "Coralogix",
            dependencies: [
                .target(name: "Coralogix-Internal"),
                .target(name: "CrashReporter")
            ],
            path: "Coralogix/Sources/"
        )
    ]
)
