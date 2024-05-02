# coralogix-ios-sdk
Coralogix RUM SDK for iOS

## Installation

To install this package, import `url here` in spm.

```swift
        let options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain,
                                               userContext: nil,
                                               environment: "ENVIRONMENT",
                                               application: "APP-NAME",
                                               version: "APP-VERSION",
                                               publicKey: "TOKEN",
                                               ignoreUrls: [],
                                               ignoreErrors: [],
                                               customDomainUrl: "",
                                               labels: ["String" : Any],
                                               debug: false)
        self.coralogixRum = CoralogixRum(options: options)
```
