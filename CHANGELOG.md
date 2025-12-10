# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.2] - 2025-11-02

### Added
- Added validation for conflict between `body` and `multipartData` in requests
- Added new error type `NetworkError.conflictingBodyTypes` for better error reporting
- Added `RequestBody(formURLEncoded:)` convenience initializer for form URL encoded requests
- Added `Content-Length` header for multipart form data requests
- Race condition protection for `baseURL` (local copy captured at request start)

### Improved
- Improved code comments and documentation
- Enhanced error messages for better debugging
- Better handling of empty responses with `emptyResponseHandler`

### Fixed
- Fixed potential race condition when `baseURL` is updated during request execution
- Fixed error handling for conflicting body types
- Improved documentation for retry logic after token refresh

### Documentation
- Added comprehensive API reference documentation (API.md)
- Added Russian language documentation (README_RU.md, API_RU.md)
- Enhanced README with detailed examples and best practices
- Added project roadmap and improvement plan (ROADMAP.md)
- Added open source checklist (OPEN_SOURCE_CHECKLIST.md)

### Testing
- Expanded test coverage to 21 tests
- Added tests for query parameters, form URL encoded, multipart data
- Added tests for error handling, retry policy, token refresh
- Added tests for User-Agent configuration and Content-Length headers

---

## [1.2.1] - 2025-11-02

### Added
- Swift 6.0 language version requirement
- Improved error handling and error types

### Changed
- Updated minimum Swift version to 6.0
- Enhanced error messages for better debugging

---

## [1.2.0] - 2025-11-02

### Added
- **Progress Tracking**: Full support for upload and download progress tracking
  - `NetworkProgress` class with `@Published` `fractionCompleted` property
  - SwiftUI integration support via `ObservableObject`
  - Automatic progress updates for both uploads and downloads
- **User-Agent Configuration**: Automatic User-Agent header generation
  - `UserAgentConfiguration` struct for custom User-Agent strings
  - Automatic inclusion of app name, version, bundle ID, build number, and OS version
  - EKNetwork version included in User-Agent string
- **Dynamic Base URL**: Ability to change base URL at runtime
  - `updateBaseURL(_:)` method for switching environments
  - Thread-safe base URL updates
- **Extended Retry Policy**: Enhanced retry mechanism
  - Better error type detection in default retry policy
  - Support for custom retry conditions per request

### Improved
- Better handling of empty responses
- Enhanced error reporting with more context
- Improved logging with structured logging via `os.Logger`

---

## [1.1.2] - 2025-11-02

### Fixed
- Minor bug fixes and stability improvements

---

## [1.1.1] - 2025-11-02

### Fixed
- Bug fixes and stability improvements

---

## [1.1.0] - 2025-10-31

### Added
- **Multipart Form Data Support**: Full support for file uploads
  - `MultipartFormData` struct for building multipart requests
  - Support for multiple parts with different MIME types
  - Automatic boundary generation and encoding
- **Form URL Encoded Support**: Support for `application/x-www-form-urlencoded` requests
  - `RequestBody.formURLEncoded` case for form data
  - Automatic parameter encoding
- **Raw Data Body**: Support for binary and pre-encoded data
  - `RequestBody.raw(Data)` for sending raw binary data
  - Custom content type support for raw data
- **Stream Body**: Support for large file uploads via streams
  - `RequestBody.stream(InputStream)` for streaming uploads
  - Efficient handling of large files without loading into memory
- **Custom JSON Encoders/Decoders**: Per-request JSON configuration
  - `jsonEncoder` and `jsonDecoder` properties in `NetworkRequest`
  - Custom date encoding/decoding strategies
  - Custom key encoding/decoding strategies (snake_case, camelCase, etc.)

### Improved
- Better error handling for different body types
- Enhanced request validation

---

## [1.0.1] - 2025-08-20

### Fixed
- Initial bug fixes and stability improvements

---

## [1.0.0] - 2025-06-15

### Added
- **Initial Release**: First stable version of EKNetwork
- **Type-Safe API**: Protocol-based request definition with `NetworkRequest`
  - Associated type `Response` for compile-time type safety
  - Automatic response decoding to specified types
- **Async/Await Support**: Native Swift concurrency support
  - Full `async/await` API without callbacks
  - Modern Swift concurrency patterns
- **Automatic Token Refresh**: Built-in token refresh mechanism
  - `TokenRefreshProvider` protocol for custom refresh logic
  - Automatic retry on 401 Unauthorized responses
  - Seamless token refresh integration
- **Retry Policy**: Flexible retry mechanism
  - `RetryPolicy` struct with configurable retry count and delay
  - Custom retry condition closures
  - Default retry policy for common error scenarios
- **Error Handling**: Comprehensive error types
  - `NetworkError` enum for network-specific errors
  - `HTTPError` struct for HTTP status code errors
  - Custom error decoder support
- **HTTP Methods**: Support for all standard HTTP methods
  - GET, POST, PUT, DELETE, PATCH
- **Query Parameters**: Automatic URL query parameter encoding
- **Custom Headers**: Support for custom HTTP headers per request
- **JSON Body**: Support for JSON request bodies with `Encodable` types
- **Empty Response Handling**: Support for endpoints that return only status codes
  - `EmptyResponse` type for success-only responses
  - `StatusCodeResponse` for status code and headers only
- **Protocol Abstractions**: Testability and dependency injection
  - `URLSessionProtocol` for mocking URLSession
  - `NetworkManaging` protocol for testing
- **Logging**: Built-in logging support via `os.Logger`
  - Request/response logging
  - Error logging with context

---

## Types of Changes

- `Added` - for new features
- `Changed` - for changes in existing functionality
- `Deprecated` - for soon-to-be removed features
- `Removed` - for removed features
- `Fixed` - for any bug fixes
- `Security` - in case of vulnerabilities

---

## Migration Guide

### From 1.0.0 to 1.1.0

If you were using basic JSON requests, no changes are required. New features are opt-in:

```swift
// New: Multipart uploads
var multipartData: MultipartFormData? {
    var data = MultipartFormData()
    data.addPart(name: "file", data: fileData, mimeType: "image/jpeg")
    return data
}

// New: Form URL encoded
var body: RequestBody? {
    RequestBody(formURLEncoded: ["key": "value"])
}
```

### From 1.1.0 to 1.2.0

New features are backward compatible:

```swift
// New: Progress tracking
let progress = NetworkProgress()
var progress: NetworkProgress? { progress }

// New: User-Agent configuration
let manager = NetworkManager(
    baseURL: baseURL,
    userAgentConfiguration: UserAgentConfiguration(...)
)

// New: Dynamic base URL
manager.updateBaseURL(newURL)
```

### From 1.2.0 to 1.2.2

No breaking changes. New validation prevents common mistakes:

```swift
// Now validated: Cannot set both body and multipartData
// This will throw NetworkError.conflictingBodyTypes
```

---

*For detailed migration instructions, see [README.md](README.md) and [API.md](API.md)*
