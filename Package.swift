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
        //.package(url: "https://github.com/microsoft/plcrashreporter", from: "1.11.1")
    ],
    targets: [
        .binaryTarget(
            name: "CrashReporter",
            path: "Coralogix/Frameworks/PLCrashReporter/CrashReporter.xcframework"
        ),
        .target(
            name: "Coralogix",
            dependencies: [
                //.product(name: "crashreporter", package: "plcrashreporter")
                .target(name: "CrashReporter"),
            ],
            path: "Coralogix/Sources/"
        )
    ]
)
