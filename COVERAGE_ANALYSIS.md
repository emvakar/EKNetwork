# Code Coverage Analysis

## Current Coverage: 72.75%

### Why Coverage is Low

The main reason for low coverage is that **a significant portion of the code consists of fallback mechanisms and edge cases that are difficult to test** in a normal testing environment.

## Uncovered Code Areas

### 1. EKNetworkVersion Fallback Paths (Major Contributor)

**Location:** `Sources/EKNetwork/NetworkManager.swift:20-120`

**Problem:** The `EKNetworkVersion` enum has multiple fallback mechanisms to determine the framework version:

1. ✅ **Priority 1: Embedded version** (ALWAYS USED) - `Version.swift` file
2. ❌ **Priority 2: Environment variable** - `EKNETWORK_VERSION` env var
3. ❌ **Priority 3: Bundle version** - From `CFBundleShortVersionString` or `CFBundleVersion`
4. ❌ **Priority 4: Git tag from framework path** - `getGitVersion(from: frameworkPath)`
5. ❌ **Priority 5: Git tag from current directory** - `getGitVersion(from: nil)`

**Why not covered:**
- Priority 1 always succeeds (Version.swift always has a value)
- Priorities 2-5 are fallbacks that only execute if Priority 1 fails
- In tests, Version.swift always contains a version, so fallbacks never execute
- `getGitVersion()` function is completely untested (73+ lines)

**Impact:** ~127 lines of code (27% of total uncovered lines)

### 2. UserAgentConfiguration Fallback Paths

**Location:** `Sources/EKNetwork/NetworkManager.swift:146-178`

**Problem:** Some fallback paths in `UserAgentConfiguration.init()` are not covered:
- Bundle fallbacks when values are not provided
- Different OS version detection paths (UIKit vs AppKit vs other)

**Why not covered:**
- Tests typically provide explicit values
- Platform-specific code paths (#if canImport) may not be tested on all platforms

**Impact:** ~15-20 lines

### 3. Error Handling Edge Cases

**Location:** Various locations in `NetworkManager.swift`

**Problem:** Some error paths are difficult to trigger:
- Network errors that don't match retry policy
- Specific URLError codes
- Edge cases in URL construction

**Why not covered:**
- Requires specific error conditions
- Some errors are platform/environment specific

**Impact:** ~20-30 lines

### 4. ProgressDelegate Edge Cases

**Location:** `Sources/EKNetwork/NetworkManager.swift:791-835`

**Problem:** Some delegate methods may not be fully covered:
- Edge cases in progress calculation
- Error handling in delegate methods

**Why not covered:**
- Progress tracking requires specific URLSession delegate setup
- Some delegate methods are called by the system, not directly testable

**Impact:** ~10-15 lines

### 5. Retry Policy Edge Cases

**Location:** `Sources/EKNetwork/NetworkManager.swift:498-518`

**Problem:** Some retry policy logic may not be fully covered:
- Specific error type checks in default `shouldRetry` closure
- Edge cases in error type detection

**Why not covered:**
- Requires specific error types that are hard to simulate
- Some error type checks use string matching which may not be triggered

**Impact:** ~10-15 lines

## Statistics

- **Total lines:** 466
- **Covered lines:** 339
- **Uncovered lines:** 127
- **Coverage:** 72.75%
- **Target:** 98%
- **Gap:** 25.25% (127 lines)

## Recommendations

### Option 1: Exclude Fallback Code from Coverage (Recommended)

Since `EKNetworkVersion` fallback paths are defensive code that should never execute in normal operation, consider excluding them from coverage requirements:

```bash
# In coverage.sh, exclude EKNetworkVersion entirely
-ignore-filename-regex=".*Tests.*|.*Version\.swift|.*EKNetworkVersion"
```

**Pros:**
- Focuses coverage on actual business logic
- Fallback code is defensive and rarely executes
- More realistic coverage metric

**Cons:**
- Technically lowers coverage percentage
- May miss actual bugs in fallback code

### Option 2: Add Tests for Fallback Paths

Create tests that simulate conditions where fallbacks are needed:

1. **Test EKNetworkVersion fallbacks:**
   - Mock empty Version.swift
   - Set environment variables
   - Mock Bundle responses
   - Test git version detection (if possible)

2. **Test UserAgentConfiguration fallbacks:**
   - Test with nil values
   - Test on different platforms
   - Test Bundle fallbacks

3. **Test error edge cases:**
   - Create specific error conditions
   - Test all URLError codes
   - Test retry policy edge cases

**Pros:**
- True 98%+ coverage
- Tests defensive code
- Catches potential bugs

**Cons:**
- Requires complex mocking
- Some code may be untestable (git commands, system calls)
- Time-consuming

### Option 3: Hybrid Approach (Best)

1. **Exclude clearly untestable code** (git commands, system processes)
2. **Add tests for testable fallbacks** (Bundle, environment variables)
3. **Focus coverage on business logic** (NetworkManager core functionality)

**Expected Result:** ~95-98% coverage of testable code

## Action Plan

### Immediate Actions

1. ✅ Document uncovered areas (this file)
2. ⏳ Decide on coverage strategy (exclude vs test)
3. ⏳ Update coverage script if excluding code
4. ⏳ Add tests for testable fallbacks

### Long-term Actions

1. Refactor `EKNetworkVersion` to be more testable
2. Add integration tests for edge cases
3. Consider using dependency injection for system calls

## Conclusion

The low coverage (72.75%) is primarily due to:
- **Defensive fallback code** that rarely executes (EKNetworkVersion)
- **System-level code** that's difficult to test (git commands, Process)
- **Platform-specific code** that may not run in test environment

The **core business logic** (NetworkManager, request handling, retry logic) is well-tested. The uncovered code is mostly defensive fallbacks and system integration code.

**Recommendation:** Exclude untestable fallback code from coverage requirements, focus on testing business logic, and aim for 95%+ coverage of testable code.

