# DemoApp UI Tests

This directory contains UI tests for the DemoApp iOS application.

```bash
cd ..
xcodebuild test -scheme DemoAppSwift -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'
```
xcodebuild test -scheme DemoAppSwift -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:DemoAppUITests
