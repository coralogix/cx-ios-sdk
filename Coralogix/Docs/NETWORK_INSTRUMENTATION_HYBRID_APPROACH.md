# Network Instrumentation: Hybrid Approach

**Date:** February 2026  
**Author:** iOS SDK Team  
**Status:** Proposed Solution

---

## Executive Summary

We propose implementing a **hybrid network instrumentation approach** that combines:
1. Our current rich data collection capabilities
2. universal coverage strategy (used since 2015)

**Result:** Automatic support for **all** networking libraries (Alamofire, AFNetworking, custom implementations) while maintaining full metrics and payload recording capabilities.

---

## Problem Statement

### Current Issue
After removing `objc_getClassList()` (to prevent CloudKit `+initialize` side effects causing UserDefaults corruption), our SDK no longer automatically instruments third-party networking libraries like **Alamofire** and **AFNetworking**.

### Impact
- ❌ Network requests made via Alamofire are **not tracked**
- ❌ Requires manual configuration for each third-party library
- ❌ Poor developer experience
- ❌ Incomplete RUM data for customers using popular networking libraries

---

## Proposed Solution: Hybrid Approach

### Strategy Overview

Combine **two complementary techniques**:

1. **Existing Approach** (Rich Data Collection)
   - Completion handler wrappers → Full response data + payloads
   - Delegate method swizzling → URLSessionTaskMetrics (timing, sizes, protocols)
   - Works perfectly for: Standard URLSession, async/await

2. **New's Approach** (Universal Coverage) - **NEW**
   - `setState:` swizzling → Fallback for third-party libraries
   - Smart class discovery → No dangerous `objc_getClassList()`
   - Battle-tested since 2015 in AFNetworking & New

3. **Deduplication Layer**
   - Prevents double-logging via associated object flags
   - Prioritizes rich data when available, falls back to basic data

---

## Technical Architecture

### Classes That Will Be Swizzled

#### 1. URLSession (Existing)
- **Purpose:** Task creation, header injection, completion wrapping
- **Risk:** Low (standard Apple API)

#### 2. NSURLSessionTask Subclasses (Existing + Enhanced)
- **Discovery Method:** Create temporary session, traverse class hierarchy (New's algorithm)
- **Typical Classes Found:**
  - `NSURLSessionDataTask`
  - `NSURLSessionUploadTask`
  - `NSURLSessionDownloadTask`
  - `__NSCFLocalDataTask` (iOS private)
  - `__NSCFURLLocalSessionConnection` (iOS private)
- **Risk:** Low (proven safe by New/AFNetworking for 9+ years)

#### 3. User Delegate Classes (Optional, Existing)
- **Only if explicitly configured** via `delegateClassesToInstrument`
- **Risk:** Low (manual opt-in only)

### Methods That Will Be Swizzled

| Class | Method | Purpose | Status |
|-------|--------|---------|--------|
| URLSession | `dataTask(with:completionHandler:)` | Wrap completion, inject headers | ✅ Existing |
| URLSession | `uploadTask(with:from:completionHandler:)` | Wrap completion, inject headers | ✅ Existing |
| URLSession | `data(for:)` (async) | Detect async/await context | ✅ Existing |
| NSURLSessionTask | `resume()` | Track start, inject headers | ✅ Existing |
| NSURLSessionTask | **`setState:`** | **Track completion (fallback)** | 🆕 **NEW** |
| Delegates | `urlSession(_:task:didFinishCollecting:)` | Capture metrics | ✅ Existing |
| Delegates | `urlSession(_:task:didCompleteWithError:)` | Track completion | ✅ Existing |

---

## Request Flow Examples

### Scenario 1: Standard URLSession Request
```text
┌─────────────────────────────────────────────────────────┐
│ 1. Task Creation                                        │
│    • dataTask(with:completionHandler:) swizzled         │
│    • Inject tracing headers (W3C Trace Context)         │
│    • Wrap completion handler                            │
│    • Assign unique task ID                              │
├─────────────────────────────────────────────────────────┤
│ 2. Task Start (resume)                                  │
│    • resume() swizzled                                  │
│    • Log start time, URL, method                        │
│    • Store in request map                               │
├─────────────────────────────────────────────────────────┤
│ 3. Request Completes                                    │
│    • Completion wrapper fires                           │
│    • Log: status, headers, body, duration               │
│    • Set "logged" flag ✅                               │
│    • Call original completion handler                   │
├─────────────────────────────────────────────────────────┤
│ 4. State Change to .completed                           │
│    • setState: fires (NEW)                              │
│    • Check "logged" flag → Already logged ✅            │
│    • SKIP (no duplicate)                                │
└─────────────────────────────────────────────────────────┘

Result: ⭐⭐⭐⭐⭐ Full data captured, no duplicates
```

### Scenario 2: Async/Await Request
```text
┌─────────────────────────────────────────────────────────┐
│ 1. Task Creation                                        │
│    • data(for:) creates internal task                   │
│    • No explicit completion handler                     │
├─────────────────────────────────────────────────────────┤
│ 2. Task Start (resume)                                  │
│    • resume() swizzled                                  │
│    • Detect async context (iOS 16+: Task.basePriority) │
│    • Inject headers via KVC                             │
│    • Set FakeDelegate to capture metrics                │
├─────────────────────────────────────────────────────────┤
│ 3. Request Completes                                    │
│    • FakeDelegate.didFinishCollecting fires             │
│    • Log: URLSessionTaskMetrics + response              │
│    • Set "logged" flag ✅                               │
├─────────────────────────────────────────────────────────┤
│ 4. State Change to .completed                           │
│    • setState: fires (NEW)                              │
│    • Check "logged" flag → Already logged ✅            │
│    • SKIP (no duplicate)                                │
└─────────────────────────────────────────────────────────┘

Result: ⭐⭐⭐⭐⭐ Full data + metrics, no duplicates
```

### Scenario 3: Alamofire Request (NEW - Currently Broken)
```text
┌─────────────────────────────────────────────────────────┐
│ 1. Task Creation (Alamofire Internal)                  │
│    • Alamofire creates task with its own delegate      │
│    • We don't control this layer                        │
├─────────────────────────────────────────────────────────┤
│ 2. Task Start (resume)                                  │
│    • resume() swizzled fires                            │
│    • Log start time, URL, method                        │
│    • Inject headers (if possible)                       │
├─────────────────────────────────────────────────────────┤
│ 3. Request Completes (Alamofire Internal)              │
│    • Alamofire handles response internally              │
│    • Our completion wrapper NOT called                  │
│    • Our delegate methods NOT called                    │
│    • "logged" flag NOT set                              │
├─────────────────────────────────────────────────────────┤
│ 4. State Change to .completed ✅                        │
│    • setState: fires (NEW)                              │
│    • Check "logged" flag → NOT set                      │
│    • Access task.response, task.error                   │
│    • Log: status, URL, duration, error                  │
│    • Set "logged" flag ✅                               │
└─────────────────────────────────────────────────────────┘

Result: ⭐⭐⭐ Basic data captured (no metrics), no duplicates
```

---

## Data Quality Comparison

| Scenario | Data Source | Status Code | Headers | Body | Metrics | Duration | Duplicates |
|----------|-------------|-------------|---------|------|---------|----------|------------|
| Standard URLSession | Completion | ✅ | ✅ | ✅ | ❌ | ✅ | No |
| Async/Await | FakeDelegate | ✅ | ✅ | ✅ | ✅ | ✅ | No |
| Alamofire (Current) | **None** | ❌ | ❌ | ❌ | ❌ | ❌ | N/A |
| **Alamofire (NEW)** | **setState:** | ✅ | ✅ | ❌ | ❌ | ✅ | **No** |
| AFNetworking (NEW) | setState: | ✅ | ✅ | ❌ | ❌ | ✅ | No |

**Legend:**
- ✅ Available
- ❌ Not Available
- ⭐⭐⭐⭐⭐ Full data (completion wrapper or delegate)
- ⭐⭐⭐ Basic data (setState: fallback)

---

## Implementation Details

### 1. New's Class Discovery (Safe)
```swift
func discoverTaskClasses() -> [AnyClass] {
    // Create temporary session with ephemeral config
    let config = URLSessionConfiguration.ephemeralSessionConfiguration()
    let session = URLSession(configuration: config)
    
    // Create dummy task to discover its class hierarchy
    let dummyTask = session.dataTask(with: URL(string: "")!)
    var currentClass: AnyClass? = type(of: dummyTask)
    var result: [AnyClass] = []
    
    let setStateSelector = NSSelectorFromString("setState:")
    
    // Traverse hierarchy, collect classes that implement setState:
    while let cls = currentClass,
          class_getInstanceMethod(cls, setStateSelector) != nil {
        
        let superClass = class_getSuperclass(cls)
        let classIMP = method_getImplementation(
            class_getInstanceMethod(cls, setStateSelector)!
        )
        let superIMP = method_getImplementation(
            class_getInstanceMethod(superClass, setStateSelector)!
        )
        
        // Only add if implementation differs from superclass
        if classIMP != superIMP {
            result.append(cls)
        }
        
        currentClass = superClass
    }
    
    // Cleanup
    dummyTask.cancel()
    session.finishTasksAndInvalidate()
    
    return result
}
```

**Why This Is Safe:**
- ✅ No `objc_getClassList()` (avoids `+initialize` side effects)
- ✅ Only discovers classes actually used by URLSession
- ✅ Proven safe by AFNetworking (2015) and New (2019+)
- ✅ Creates temporary session that's immediately cleaned up

### 2. setState: Swizzling
```swift
func swizzleSetState(on classes: [AnyClass]) {
    let selector = NSSelectorFromString("setState:")
    
    for cls in classes {
        swizzle(cls, selector) { (task: NSURLSessionTask, state: NSURLSessionTaskState) in
            // Call original first
            callOriginal(task, state)
            
            // Only handle .completed state
            guard state == .completed else { return }
            
            // Check if already logged
            if isAlreadyLogged(task) { return }
            
            // Fallback logging
            logTaskCompletion(task)
            markAsLogged(task)
        }
    }
}
```

### 3. Deduplication Logic
```swift
private static var loggedKey: UInt8 = 0

func markAsLogged(_ task: NSURLSessionTask) {
    objc_setAssociatedObject(task, &loggedKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}

func isAlreadyLogged(_ task: NSURLSessionTask) -> Bool {
    return objc_getAssociatedObject(task, &loggedKey) != nil
}
```

**Applied In:**
- ✅ Completion handler wrappers → Set flag after logging
- ✅ Delegate methods (`didFinishCollecting`) → Set flag after logging
- ✅ `setState:` → Check flag before logging

---

## Benefits

### For Customers

| Benefit | Impact |
|---------|--------|
| 🎉 **Alamofire works automatically** | No configuration needed, complete RUM data |
| 🎉 **AFNetworking works automatically** | Legacy apps supported |
| 🎉 **Any networking library works** | Future-proof against new libraries |
| 📊 **Complete network visibility** | No blind spots in RUM data |
| 🚀 **Zero-config experience** | Better DX, faster integration |

### For Us

| Benefit | Impact |
|---------|--------|
| 🛡️ **Battle-tested approach** | Proven by New (millions of apps) |
| 🔒 **Safe implementation** | No dangerous class scanning |
| 🧹 **Cleaner architecture** | Clear fallback strategy |
| 📈 **Better RUM data** | More complete network instrumentation |
| 💰 **Competitive advantage** | Matches/exceeds competitor capabilities |

---

## Risks & Mitigation

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| setState: swizzling conflicts | Low | Medium | Use New's proven approach, tested for 9 years |
| Double logging edge cases | Low | Low | Robust deduplication with associated objects |
| iOS version compatibility | Low | Medium | Covered by New's extensive testing |
| Performance overhead | Very Low | Low | Minimal - one extra check per request |

### Testing Strategy
1. ✅ **Unit Tests**: Verify deduplication logic
2. ✅ **UI Tests**: Test Alamofire, AFNetworking, standard URLSession
3. ✅ **Integration Tests**: Run DemoApp with all networking scenarios
4. ✅ **iOS Version Coverage**: Test on iOS 13-18 (simulator + real devices)

---

## Backward Compatibility

### SDK Behavior
- ✅ **Existing implementations**: Zero breaking changes
- ✅ **Current API**: No changes required
- ✅ **Configuration**: Existing options still work
- ✅ **Data format**: Unchanged

### Migration
- ✅ **Automatic**: No customer action required
- ✅ **Opt-out**: Can disable via `enableSwizzling = false`

---

## Performance Impact

### Memory
- **+8 bytes per task** (associated object for deduplication flag)
- **+~500 bytes** (class discovery results cached)

### CPU
- **+1 check per request** (flag lookup in setState:)
- **Negligible**: < 0.1ms per request

### Network
- **No change**: Same data sent, just more complete

---

## Alternatives Considered

### Alternative 1: Pure New Approach
- ❌ **Loses URLSessionTaskMetrics** (timing, sizes, protocols)
- ❌ **Loses payload recording** capability
- ❌ **Less detailed data** for standard requests

### Alternative 2: Manual Configuration Only
- ❌ **Poor developer experience**
- ❌ **Incomplete data** (customers won't configure)
- ❌ **Support burden** (constant configuration questions)

### Alternative 3: Do Nothing
- ❌ **Alamofire broken** (significant customer pain)
- ❌ **Incomplete RUM data**
- ❌ **Competitive disadvantage**

---

## Recommendation

✅ **Proceed with Hybrid Approach**

**Justification:**
1. Proven safe by industry leaders (AFNetworking, New)
2. Solves real customer pain (Alamofire support)
3. Maintains all existing capabilities
4. Zero breaking changes
5. Competitive parity with New, Datadog

**Timeline Estimate:**
- Implementation: 2-3 days
- Testing: 2-3 days
- Code review: 1 day
- **Total: ~1 week**

---

## References

- [New iOS SDK - Network Tracking](https://github.com/getNew/New-cocoa)
- [AFNetworking - URLSession Task Discovery](https://github.com/AFNetworking/AFNetworking/blob/master/AFNetworking/AFURLSessionManager.m#L349-L418)
- [New Decision Log - Alamofire Support](https://github.com/getNew/New-cocoa/blob/main/develop-docs/DECISIONS.md)

---

## Appendix: Code Locations

### Files to Modify
1. `Coralogix/Sources/Otel/URLSession/URLSessionInstrumentation.swift`
   - Add class discovery method
   - Add setState: swizzling
   - Add deduplication flag logic
   - Add fallback logging method

2. `Coralogix/Sources/Otel/URLSession/InstrumentationUtils.swift` (Optional)
   - Extract class discovery to utility file

### Estimated LOC Changes
- **Added:** ~150 lines
- **Modified:** ~50 lines
- **Net Change:** +200 lines

---

**Questions? Contact the iOS SDK Team**
