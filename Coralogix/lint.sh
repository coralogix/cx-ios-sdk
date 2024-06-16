#!/bin/sh

# Run SwiftLint
swiftlint lint --config swiftlint.yml

# Build the package
swift build
