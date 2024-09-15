# SDKSampler

The `SDKSampler` is a struct that implements the `SamplerProtocol` and is used to determine whether the SDK should be initialized based on a defined sample rate. This helps control the initialization and event sending behavior of the SDK, allowing for more efficient usage of resources.

### Properties

-   `public let sampleRate: Int`  
    A value between `0.0` and `100.0` that represents the percentage chance that the SDK will be initialized.
    -   A `0` value means the SDK will not be initialized.
    -   A `100` value means the SDK will always be initialized and all events will be sent.

### Initializer

-   `public init(sampleRate: Int)`  
    Initializes the `SDKSampler` with a sample rate. The sample rate is clamped between `0` and `100`, ensuring it stays within valid bounds.
    
    **Parameters:**
    
    -   `sampleRate: Int` – The percentage chance that the SDK will be initialized.

### Method

-   `public func shouldInitialized() -> Bool`  
    This method returns a random value to decide whether the SDK should be initialized based on the provided `sampleRate`. If the random value falls within the range of the sample rate, it returns `true`, otherwise it returns `false`.

### Usage Example

swift

```swift
let sdkSampler = SDKSampler(sampleRate: 50)

if sdkSampler.shouldInitialized() {
    print("SDK will be initialized")
} else {
    print("SDK initialization skipped")
}

// In this example, the `SDKSampler` is created with a `sampleRate` of 50, meaning there is a 50% chance the SDK will be initialized.
```

### Key Points

-   **Dynamic Control:** The `SDKSampler` allows for dynamic control over the SDK's initialization, based on random sampling.
-   **Efficiency:** Using a sample rate helps reduce the load on system resources by initializing the SDK only when necessary.
-   **Range Check:** The `sampleRate` is always clamped between 0 and 100 to ensure that it remains within valid bounds.