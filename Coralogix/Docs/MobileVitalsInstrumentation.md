# Mobile Vitals Instrumentation

The Mobile Vitals Instrumentation in our SDK automatically detects and monitors key performance metrics related to application responsiveness and rendering performance. This allows developers to track vital aspects of the app's user experience and performance without needing manual intervention. The SDK currently supports automatic detection of the following metrics:

## 1. Application Not Responsive (ANR)

**Application Not Responsive (ANR)** occurs when the app's main thread is blocked for too long, causing the app to appear unresponsive to the user. The SDK automatically detects ANR events by monitoring the time taken for the main thread to process tasks.

- **Detection Criteria:**  
  ANR is detected when the main thread is blocked for more than a specified threshold, typically 5 seconds.
  
- **Automatic Detection Process:**
  - The SDK monitors the main thread's event loop and logs an ANR event if the loop is stalled for an extended period.
  
- **Reported Metric:**
  - The SDK reports the ANR event through a notification, allowing developers to analyze the occurrence and address any underlying performance issues.
  
## 2. Frames Per Second (FPS)

**Frames Per Second (FPS)** is a key indicator of the rendering performance of the application. A low FPS can lead to a choppy and unresponsive user interface, negatively impacting the user experience.

- **Detection Criteria:**  
  FPS is tracked by monitoring how many frames are rendered per second during a given time interval, typically over 5 seconds.
  
- **Automatic Detection Process:**
  - The SDK uses the `CADisplayLink` to monitor the refresh rate of the app’s UI and calculates the average FPS over a predefined period.
  
- **Reported Metric:**
  - The SDK reports the average FPS over the monitoring period through notifications, providing insights into the rendering performance of the app.
  
## 3. Warm Start

A **Warm Start** refers to when the app is launched while it is still running in memory (i.e., the app was in the background). Warm starts are generally faster compared to cold starts.

- **Detection Criteria:**  
  A warm start is detected when the app transitions from the background to the foreground and resumes its state from memory.

- **Automatic Detection Process:**
  - The SDK tracks when the app moves from the background to the foreground and logs it as a warm start event.
  
- **Reported Metric:**
  - The SDK captures and reports the time taken for the app to fully resume, providing insights into the app's performance when returning from the background.
  
## 4. Cold Start

A **Cold Start** refers to when the app is launched from scratch, meaning the app is completely terminated before the launch. Cold starts take longer as the app has to initialize its UI, data, and other resources from the beginning.

- **Detection Criteria:**  
  A cold start is detected when the app is launched from a completely terminated state (i.e., not running in the background).

- **Automatic Detection Process:**
  - The SDK monitors the app launch sequence from the very start and records the time taken for the app to fully initialize and render its first screen.
  
- **Reported Metric:**
  - The SDK logs the duration of the cold start, allowing developers to identify bottlenecks during app initialization.
  

