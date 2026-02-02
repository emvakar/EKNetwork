# EKNetwork Roadmap & Improvement Plan

This document outlines the planned improvements and known issues for EKNetwork.

## 🎯 High Priority Issues

### Issue #1: Memory Leak in ProgressDelegate
**Status:** 🔴 Critical  
**Location:** `NetworkManager.swift:729-731`

**Problem:** Creating a new `URLSession` with `ProgressDelegate` for each progress request can cause memory leaks.

**Solution:**
- Use a shared `URLSession` with a delegate manager
- Or explicitly invalidate session after request completion

**Related Issue:** See GitHub issue for details

---

### Issue #2: Force Unwrap in MultipartFormData
**Status:** 🟡 Medium  
**Location:** `NetworkManager.swift:273-282`

**Problem:** Force unwrap (`!`) is used when converting strings to Data, which can cause crashes.

**Solution:**
- Use safe conversion with error handling
- Or use `Data(contentsOf:)` with validation

**Related Issue:** See GitHub issue for details

---

## 🟡 Medium Priority Issues

### Issue #3: ~~Race Condition in updateBaseURL~~ ✅ Resolved (v1.4.1)
**Status:** ✅ Resolved  
**Resolved in:** v1.4.1 — Base URL is now provided via closure `() -> URL`; `updateBaseURL` was removed. Each request calls the closure, so there is no shared mutable base URL and no race condition.

---

### Issue #4: Unsafe String(describing:) Usage in RetryPolicy
**Status:** 🟡 Medium  
**Location:** `NetworkManager.swift:507-509`

**Problem:** Using `String(describing: type(of: $0))` for type checking is unreliable.

**Solution:**
- Use protocols to mark errors that shouldn't be retried
- Or use `is` for type checking

**Related Issue:** See GitHub issue for details

---

### Issue #5: Missing Task Cancellation Handling in Retry Logic
**Status:** 🟡 Medium  
**Location:** `NetworkManager.swift:772-774`

**Problem:** Retry logic doesn't check if Task was cancelled, leading to unnecessary retries.

**Solution:**
- Add `Task.isCancelled` check before retry
- Throw `CancellationError` on cancellation

**Related Issue:** See GitHub issue for details

---

## 🟢 Low Priority Issues

### Issue #6: ~~Missing URL Validation in updateBaseURL~~ ✅ N/A (v1.4.1)
**Status:** ✅ N/A  
**Resolved in:** v1.4.1 — `updateBaseURL` was removed; base URL is now a closure. Invalid URL from the closure still leads to `NetworkError.invalidURL` when building the request (e.g. when `URLComponents` fails).

---

### Issue #7: Query Parameters Overwrite Issue
**Status:** 🟢 Low  
**Location:** `NetworkManager.swift:632-634`

**Problem:** Existing query parameters in URL may be overwritten when adding new ones.

**Solution:**
- Check existing query parameters
- Merge them with new ones

**Related Issue:** See GitHub issue for details

---

### Issue #8: Missing Content-Length Validation for Stream
**Status:** 🟢 Low  
**Location:** `NetworkManager.swift:691-695`

**Problem:** Content-Length is not set for streams, which may cause issues with some servers.

**Solution:**
- Document this behavior
- Or provide option to set Content-Length

**Related Issue:** See GitHub issue for details

---

### Issue #9: ProgressDelegate Task Cancellation
**Status:** 🟢 Low  
**Location:** `NetworkManager.swift:807-809, 822-824, 830-832`

**Problem:** `Task { @MainActor in }` in `ProgressDelegate` may continue after request cancellation.

**Solution:**
- Check `Task.isCancelled` before updating
- Use `Task.checkCancellation()`

**Related Issue:** See GitHub issue for details

---

### Issue #10: Empty Response Handler Validation
**Status:** 🟢 Low  
**Location:** `NetworkManager.swift:410-420`

**Problem:** Empty responses throw error even when they might be valid for some requests.

**Solution:**
- Improve documentation
- Or add option to allow empty responses

**Related Issue:** See GitHub issue for details

---

## 💡 Planned Improvements

### Improvement #1: Shared URLSession for Progress Tracking
**Priority:** High  
**Status:** 📋 Planned

Use a shared `URLSession` with delegate manager for all progress requests.

**Benefits:**
- Avoid memory leaks
- Better performance
- Centralized management

**Related Issue:** See GitHub issue for details

---

### Improvement #2: Task Cancellation Support
**Priority:** High  
**Status:** 📋 Planned

Add support for cancelling requests via `Task` cancellation.

**Benefits:**
- Better request control
- Resource savings
- Modern Swift practices compliance

**Related Issue:** See GitHub issue for details

---

### Improvement #3: Improved Error Handling in RetryPolicy
**Priority:** Medium  
**Status:** 📋 Planned

Use protocols instead of string type name checking.

```swift
protocol NonRetriableError: Error {}
```

**Benefits:**
- Type safety
- Better performance
- Cleaner code

**Related Issue:** See GitHub issue for details

---

### Improvement #4: Metrics and Monitoring
**Priority:** Medium  
**Status:** 📋 Planned

Add ability to track request metrics (execution time, data size, etc.).

**Benefits:**
- Better diagnostics
- Performance monitoring
- Problem debugging

**Related Issue:** See GitHub issue for details

---

### Improvement #5: Caching Support
**Priority:** Low  
**Status:** 📋 Planned

Add optional support for response caching.

**Benefits:**
- Performance improvement
- Reduced network load
- Better UX

**Related Issue:** See GitHub issue for details

---

### Improvement #6: Enhanced Edge Cases Documentation
**Priority:** Low  
**Status:** 📋 Planned

Add more examples and documentation for edge cases (empty responses, cancellation, etc.).

**Benefits:**
- Better library understanding
- Fewer user questions
- Better developer experience

**Related Issue:** See GitHub issue for details

---

### Improvement #7: Request Validation
**Priority:** Low  
**Status:** 📋 Planned

Add request validation before sending (URL check, headers, etc.).

**Benefits:**
- Early error detection
- Better error messages
- More reliable code

**Related Issue:** See GitHub issue for details

---

### Improvement #8: URLRequest Creation Optimization
**Priority:** Low  
**Status:** 📋 Planned

Cache frequently used URLRequest components.

**Benefits:**
- Better performance
- Fewer allocations
- More efficient memory usage

**Related Issue:** See GitHub issue for details

---

## 📊 Statistics

- **Total Issues:** 10
- **Total Improvements:** 8
- **High Priority:** 2 issues, 2 improvements
- **Medium Priority:** 3 issues, 2 improvements
- **Low Priority:** 5 issues, 4 improvements

## 📝 Notes

- All issues are tracked in GitHub Issues
- Priority may change based on user feedback
- Contributions are welcome for any of these items

---

*Last updated: 2025-12-10*

