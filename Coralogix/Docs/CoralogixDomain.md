# CoralogixDomain

The `CoralogixDomain` enum represents various Coralogix account domains, each associated with a specific geographical region. Each case in the enum holds the corresponding URL for the Coralogix ingress point.

## Cases

### EU1
```swift
case EU1 = "https://ingress.eu1.rum-ingress-coralogix.com"
```
Represents the EU1 region (eu-west-1, Ireland).

### EU2
```swift
case EU2 = "https://ingress.eu2.rum-ingress-coralogix.com"
```
Represents the EU2 region (eu-north-1, Stockholm).

### US1
```swift
case US1 = "https://ingress.us1.rum-ingress-coralogix.com"
```
Represents the US1 region (us-east-2, Ohio).

### US2
```swift
case US2 = "https://ingress.us2.rum-ingress-coralogix.com"
```
Represents the US2 region (us-west-2, Oregon).

### AP1
```swift
case AP1 = "https://ingress.ap1.rum-ingress-coralogix.com"
```
Represents the AP1 region (ap-south-1, Mumbai).

### AP2
```swift
case AP2 = "https://ingress.ap2.rum-ingress-coralogix.com"
```
Represents the AP2 region (ap-southeast-1, Singapore).

## Methods
### stringValue
```swift
func stringValue() -> String
```
Returns a string representation of the enum case. The returned string corresponds to the case name.

### Example
Here is an example of how to use the stringValue method:

```swift
let domain = CoralogixDomain.EU1
print(domain.stringValue()) // Output: "EU1"
```
Example
Here is an example of how to create an instance of CoralogixDomain and access its raw value:

```swift
let domain = CoralogixDomain.US1
print(domain.rawValue) // Output: "https://ingress.us1.rum-ingress-coralogix.com"
```
