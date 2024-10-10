// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Coralogix",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(name: "Coralogix", type: .dynamic, targets: ["Coralogix"])
    ],
    dependencies: [
        .package(url: "http://github.com/microsoft/plcrashreporter.git", from: "1.11.1"),
    ],
    targets: [
        .target(
            name: "Coralogix",
            dependencies: [
                .product(name: "CrashReporter", package: "plcrashReporter"),
            ]
        )
    ]
)
