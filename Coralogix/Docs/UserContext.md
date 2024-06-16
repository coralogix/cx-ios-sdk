# UserContext

The `UserContext` struct provides information about a user, including their ID, name, email, and additional metadata. It conforms to the `Equatable` protocol, allowing for comparison between instances.

## Properties

### userId
```swift
let userId: String
```

A unique identifier for the user. This is a required property.

### userName
```swift
let userName: String
```
The name of the user. This is a required property.

### userEmail
```swift
let userEmail: String
```
The email address of the user. This is a required property.

### userMetadata
```swift
let userMetadata: [String: String]
```
A dictionary containing additional metadata about the user. This is a required property.

### Example
Here is an example of how to create an instance of UserContext:

```swift
let userContext = UserContext(
    userId: "12345",
    userName: "John Doe",
    userEmail: "john.doe@example.com",
    userMetadata: ["role": "admin", "department": "engineering"]
)
```
