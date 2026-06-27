# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

**Legend:** ✨ Added · ⚡ Improved · 🐛 Fixed · 🔄 Changed · ⚠️ Breaking · 🧪 Tests · 📝 Docs · 🔧 Infrastructure · 🚀 Migration · 📊 Technical details

## [1.6.2] - 2026-06-27

### 🔒 Security
- **Percent-encoded path traversal is now rejected.** When a request opts into `pathIsPercentEncoded`, encoded `..` sequences (`%2e%2e`, including double-encoded forms) can no longer escape the base path. Legitimate encoded segments such as `%2F` inside a single path component (e.g. GitLab file paths) keep working unchanged.
- **Request headers can no longer inject extra HTTP lines.** Header values — including the `Authorization` token — that contain carriage-return or line-feed characters are now stripped before the request is sent, closing a CRLF header-injection vector.

### 🐛 Fixed
- **Concurrent progress requests no longer interfere with each other.** Upload/download progress is now tracked per `URLSession`, so running several sessions at the same time can no longer mix up their task contexts.
- **No redundant request on HTTP 401 without a token refresher.** When no token refresher is configured, an unauthorized response now surfaces immediately instead of triggering an extra round-trip.
- **In-flight progress requests honour cancellation.** Cancelling the awaiting task now cancels the underlying upload/download instead of leaving it hanging until the network finishes.

### 🔄 Changed
- **Git-tag version resolution runs only in DEBUG builds.** Shipped (release) apps no longer spawn `/usr/bin/git` to determine the embedded EKNetwork version; the resolution chain falls back to the embedded version metadata instead.

## [1.6.1] - 2026-06-27

### 🐛 Fixed
- **Percent-encoded paths are no longer double-encoded.** Requests whose `path` already contained encoded reserved characters (e.g. GitLab `repository/files/:file_path` with `%2F`) were broken: `appendingPathComponent` re-encoded `%` into `%252F`, while the decoded form produced literal slashes — so such endpoints returned `404`. For percent-encoded paths the URL is now assembled via `percentEncodedPath`, preserving `%2F` verbatim.

### ✨ Added
- **`NetworkRequest.pathIsPercentEncoded`** — opt-in flag (default `false`). When `true`, `path` is treated as already percent-encoded and joined verbatim. Fully backward compatible: existing requests keep using `appendingPathComponent` and are unaffected.

### 🧪 Tests
- Added coverage for the real `URLSession.byteStream(for:)` bridging task, non-HTTP `StreamingError.invalidResponse`, percent-encoded path handling and path-traversal rejection. Total **175 tests**, coverage **98.15%**.

## [1.6.0] - 2026-05-09

### ✨ Added
- **Streaming responses** — first-class support for endpoints that emit data as it is produced (NDJSON, Server-Sent Events, chunked transfer):
  - New `URLSessionStreamingProtocol` with default `URLSession` conformance (bridges `URLSession.bytes(for:)` into a `Sendable` `AsyncThrowingStream<UInt8, Error>`).
  - New `NetworkStreaming` protocol exposing `stream(_:accessToken:)`.
  - New `StreamingResponse` value type with `bytes`, `lines()` (UTF-8 lines, CRLF/LF aware, blank lines skipped) and `ndjson(as:decoder:)` helpers.
  - New `StreamingError` cases: `invalidResponse`, `errorPayloadTooLarge`.
  - `NetworkManager.stream(_:accessToken:)` reuses the same request-construction pipeline as `send(_:)` (headers, access token, body, User-Agent, base URL) — no duplication of header logic in app code.
  - Streaming requests handle 401 by calling `tokenRefresher` and retrying once when `request.allowsRetry == true` (mid-stream 401s are not retried).
  - Non-2xx streaming responses drain up to 1 MiB into `HTTPError` (or run `request.errorDecoder` if provided), so error handling matches `send(_:)`.
- **`NetworkManager` initializer** gained a new optional `streamingSession: URLSessionStreamingProtocol? = nil` parameter. When omitted, the manager reuses the regular `session` if it conforms to streaming (default `URLSession` does), otherwise falls back to `URLSession.shared`. Existing initializer call sites stay source-compatible.

### 🔄 Changed
- **Internal refactor (no behaviour change)**: extracted `NetworkManager.buildURLRequest(_:accessToken:)` so both `send(_:)` and `stream(_:accessToken:)` share a single `URLRequest`-construction routine.

### 🧪 Tests
- 8 new tests covering the streaming pipeline, NDJSON decoding across chunk boundaries, CRLF handling, 401 + token refresh, custom `errorDecoder`, and default-session resolution. Total **170 tests**.

### 🚀 Migration (1.5.x → 1.6.0)
- **No source changes required.** All previous code keeps compiling and behaving identically.
- To stream a response, call `manager.stream(MyRequest(), accessToken: { token })` instead of `manager.send(...)` and consume `response.ndjson(as: Item.self)` / `response.lines()` / `response.bytes`. Headers and authentication are applied via the same `NetworkRequest.headers` and `accessToken` you already use.

## [1.5.1] - 2026-04-10

### 🔄 Changed
- Lowered the minimum deployment target to **iOS 15** for broader app compatibility.
- Package version metadata bumped to 1.5.1.

## [1.5.0] - 2026-02-11

### ✨ Added
- Expanded supported HTTP methods to include `HEAD`, `OPTIONS`, `TRACE`, and `CONNECT` alongside the existing verbs.
- Global response decoder support via `NetworkManager.responseDecoderProvider`, with per-request opt-out using `allowsResponseDecoderOverride`.

### 🔧 Infrastructure
- CI now tags and creates a GitHub release automatically after successful tests on `main`.

## [1.4.2] - 2026-02-03

### ✨ Added
- **Security & robustness**:
  - **MultipartFormData**: `encodedData()` now returns `Data?` (no force unwrap); UTF-8 encoding failures return `nil`. Name and filename in Content-Disposition are escaped (quotes and backslashes). New error `NetworkError.invalidMultipartEncoding` when encoding fails.
  - **Path normalization**: request path is normalized (trim slashes, collapse `//`); paths containing `..` are rejected with `NetworkError.invalidURL`.
  - **NonRetriableError**: new protocol; default `RetryPolicy.shouldRetry` returns `false` for errors conforming to `NonRetriableError` (replaces string-based type-name checks).
  - **Task cancellation**: the retry loop checks `Task.isCancelled` and calls `Task.checkCancellation()`; on cancellation throws `CancellationError`.
  - **Logging**: path and error messages in logs use `privacy: .private` to avoid leaking sensitive data.
  - **Convenience init**: `NetworkManager(baseURL: URL, ...)` convenience initializer for a fixed base URL.
  - **Shared progress session**: new `ProgressSessionManager` with a single shared `URLSession` and delegate for progress requests; progress requests no longer create a new session per request.

### 🔄 Changed
- **RetryPolicy**: default `shouldRetry` uses the `NonRetriableError` protocol instead of `String(describing: type(of:))`. Custom error types that should not be retried should conform to `NonRetriableError`.
- **MultipartFormData.encodedData()**: return type is now `Data?`; callers (e.g. `NetworkManager`) throw `NetworkError.invalidMultipartEncoding` when `nil`.
- **File headers**: unified Swift file headers (Created by, Copyright from file metadata).

### 🧪 Tests
- Extended test suite (`CoverageImprovementsTests`, `ExtendedTestSuite`), progress and conflicting-body tests. Total **156 tests**, coverage **99.13%** (ProgressDelegate/ProgressSessionManager excluded from the report).

## [1.4.1] - 2026-02-02

### ⚠️ Breaking
- **Base URL as a closure**: `NetworkManager` now accepts the base URL as a closure `() -> URL` instead of a stored `URL`.
  - **Initializer**: `init(baseURL: URL, ...)` → `init(baseURL: @escaping (() -> URL), ...)`.
  - **Property**: `baseURL: URL` → `baseURL: () -> URL` (read-only; call `baseURL()` to get the current URL).
  - **Removed**: `updateBaseURL(_:)` — no longer needed; pass a closure that returns the desired URL (e.g. from settings or environment) so each request uses the current value without race conditions.
- **Benefits**: dynamic base URL per request (per-environment, A/B, feature flags), no race conditions when “switching” base URL, simpler threading model.

### ✨ Added
- **Swift 6 concurrency**: `NetworkManager` now conforms to `@unchecked Sendable` so it can be used from async contexts (e.g. tests, async/await call sites) without isolation errors; callers must not mutate shared state concurrently.

### 🚀 Migration (1.4.0 → 1.4.1)
- Replace `NetworkManager(baseURL: myURL, ...)` with `NetworkManager(baseURL: { myURL }, ...)`.
- Replace `manager.baseURL` with `manager.baseURL()` where you read the current base URL.
- Replace `manager.updateBaseURL(newURL)` with a closure that returns the current base URL.

## [1.4.0] - 2025-12-11

### ✨ Added
- **CI/CD integration**: GitHub Actions workflow with automated testing and code coverage.
  - Dynamic CI badges in README showing real-time build status.
  - Automated test-count extraction and reporting.
  - Code coverage reporting and validation (99.42% threshold).
- **Swift 6.0 compatibility**: full support for Swift 6.0 strict concurrency.
  - Added `Sendable` conformance to `StatusCodeResponse` and `EmptyResponse`.
  - Updated `Package.swift` to use `swiftLanguageModes` instead of the deprecated `swiftLanguageVersions`.

### 🐛 Fixed
- **Swift 6.0 strict concurrency**: resolved all strict-concurrency errors.
  - Added `@unchecked Sendable` conformance to response types.
  - Fixed data-race warnings in tests.
- **Test compilation**: fixed all test compilation errors (`RequestBody` initializer calls, `MultipartFormData` usage, duplicate test names).
- **Documentation**: unified contact email to `emvakar@gmail.com` across all docs; added contact email to CODE_OF_CONDUCT.md.

### 🔄 Changed
- **Package configuration**: replaced deprecated `swiftLanguageVersions` with `swiftLanguageModes`.
- **Code organization**: added test suites; improved test structure and naming.

### 📊 Technical details
- Total test count: 115 (all passing) · Coverage: 99.42% (340/342 lines) · Swift 6.0 · CI/CD fully automated.

## [1.3.3] - 2025-12-10

### 🐛 Fixed
- Fixed compilation errors in `ExtendedCoverageTests.swift`:
  - Corrected `RequestBody` initializer calls to use the proper API.
  - Fixed `MultipartFormData` usage to call `addPart()` correctly.
  - Fixed `NetworkError` test to avoid redundant type checks.
  - Fixed `HTTPError` test to use `Data()` instead of `nil`.

### 🧪 Tests
- All 115 tests pass; coverage maintained at 99.42%.

## [1.3.2] - 2025-12-10

### ✨ Added
- Extended test coverage with additional edge cases.
- New test file `ExtendedCoverageTests.swift` with comprehensive tests.

### 🧪 Tests
- Total test count increased to 115; coverage maintained at 99.42%.

## [1.3.1] - 2025-12-10

### ✨ Added
- **Code coverage**: achieved 99.42% (340/342 lines).
- **Test coverage** for edge cases: `normalizeHeaders` with non-string keys/values, `NetworkRequest` default implementations (`allowsRetry`, `emptyResponseHandler`), URLComponents error handling, custom error-decoder throw path, `StatusCodeResponse`/`EmptyResponse` handlers, retry-policy and token-refresh error paths.

### 🔄 Changed
- **Code organization**: extracted `EKNetworkVersion` and `ProgressDelegate` into separate files.
- **Coverage configuration**: excluded untestable system-level code (`EKNetworkVersion` fallbacks, `ProgressDelegate` system delegates) from the coverage requirement.

### 📊 Technical details
- Total test count: 91 · Coverage: 99.42% (340/342 lines) — only 2 defensive `URLComponents` guard lines remain uncovered.

## [1.3.0] - 2025-12-10

### ✨ Added
- **Comprehensive documentation**: full API reference (API.md), Russian docs (README_RU.md, API_RU.md), enhanced README, project structure (PROJECT_STRUCTURE.md), client summary (SUMMARY.md), open-source checklist.
- **Open-source project files**: MIT License, Code of Conduct, Security policy, Contributing guidelines, Support information, Changelog.
- **GitHub configuration**: issue templates, PR template, GitHub Actions CI/CD, CODEOWNERS, FUNDING.yml.
- **Development tools**: automated GitHub issue creation script, issue process docs, roadmap.
- **Code improvements**: fixed file header comment, added `RequestBody(formURLEncoded:)` convenience initializer, enhanced `.gitignore`.

### ⚡ Improved
- **Test coverage**: expanded to 21 tests covering query params, form-url-encoded, multipart, error handling, retry policy, token refresh, User-Agent config, Content-Length headers, all HTTP methods, raw data and stream handling.
- **Package configuration**: explicit Swift 6.0 language version; cleaned up `Package.swift`.
- **Documentation quality**: all code comments translated to English; comprehensive examples; migration guides for breaking changes.

## [1.2.2] - 2025-11-02

### ✨ Added
- **Form URL encoded support**: `RequestBody(formURLEncoded:)` initializer.
- **Multipart form data**: enhanced support with better error handling and validation.
- **Progress tracking**: `NetworkProgress` observable object.
- **Retry policy**: configurable delays and custom retry logic.
- **Token refresh**: automatic refresh on 401 Unauthorized.
- **Custom error decoders**: decode server-side errors from HTTP error responses.
- **User-Agent configuration**: configurable User-Agent header generation.

### 🐛 Fixed
- **Race condition**: fixed potential race with `baseURL` updates during request execution.
- **Body validation**: prevent conflicting `body` and `multipartData` in a single request.
- **Content-Length**: ensured the header is set for multipart requests.
- **Progress updates**: fixed thread-safety issues in the progress delegate.

### 🔄 Changed
- **NetworkRequest protocol**: added optional `allowsRetry`, `emptyResponseHandler`, `jsonDecoder`, `jsonEncoder`.
- **Error handling**: more specific error types.

## [1.2.1] - 2025-11-02

### ✨ Added
- **Query parameters**: support for query parameters in requests.
- **Custom headers**: enhanced header customization.
- **Stream support**: streaming request bodies.

### 🐛 Fixed
- **URL construction**: improved with better error handling.
- **Header normalization**: fixed for case-insensitive keys.

## [1.2.0] - 2025-11-02

### ✨ Added
- **Async/await support**: full Swift concurrency.
- **Type-safe requests**: enhanced type safety with associated types.
- **Response types**: support for Codable, Data and Empty responses.
- **Error handling**: comprehensive error handling with custom error types.

### 🔄 Changed
- **API design**: redesigned for better type safety and Swift concurrency.
- **NetworkManager**: complete rewrite with modern Swift patterns.

## [1.1.2] - 2025-11-02

### ✨ Added
- Default `Accept` content type for requests.

## [1.1.1] - 2025-11-02

### ✨ Added
- Default `Content-Type` for requests.

## [1.1.0] - 2025-10-31

### ✨ Added
- **Basic network operations**: GET, POST, PUT, DELETE, PATCH.
- **JSON encoding/decoding**: automatic JSON handling.
- **Error handling**: basic handling for network errors.

### ⚡ Improved
- Better handling of empty responses.
- Configurable base URL.

## [1.0.1] - 2025-08-20

### 🔧 Infrastructure
- Project metadata and tooling updates.

## [1.0.0] - 2025-06-15

### ✨ Added
- Initial release of EKNetwork.
- Basic network request functionality.
- Support for common HTTP methods.
- JSON request/response handling.
