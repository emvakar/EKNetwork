# EKNetwork API Reference

Complete API documentation for EKNetwork library.

## Table of Contents

- [NetworkManager](#networkmanager)
- [NetworkRequest](#networkrequest)
- [HTTPMethod](#httpmethod)
- [RequestBody](#requestbody)
- [MultipartFormData](#multipartformdata)
- [RetryPolicy](#retrypolicy)
- [NetworkProgress](#networkprogress)
- [TokenRefreshProvider](#tokenrefreshprovider)
- [Streaming (NDJSON / SSE)](#streaming-ndjson--sse)
- [Error Types](#error-types)
- [Response Types](#response-types)
- [UserAgentConfiguration](#useragentconfiguration)

---

## NetworkManager

The main class for managing network requests.

### Initialization

```swift
public init(
    baseURL: @escaping (() -> URL),
    session: URLSessionProtocol = URLSession.shared,
    streamingSession: URLSessionStreamingProtocol? = nil,
    loggerSubsystem: String = "com.yourapp.networking",
    userAgentConfiguration: UserAgentConfiguration? = nil,
    responseDecoderProvider: (() -> JSONDecoder)? = nil
)
```

**Parameters:**
- `baseURL`: Closure that returns the base URL for each request. Use `{ myURL }` for a fixed URL or a closure that reads from config/environment for dynamic base URL (avoids race conditions when switching environments).
- `session`: The `URLSessionProtocol` to use for making requests (defaults to `URLSession.shared`)
- `streamingSession`: Optional session used by `stream(_:accessToken:)` for byte-stream responses (NDJSON / SSE / chunked transfer). When `nil` (default) the manager reuses `session` if it conforms to `URLSessionStreamingProtocol` (default `URLSession` does), otherwise falls back to `URLSession.shared`. Added in 1.6.0; existing call sites stay source-compatible.
- `loggerSubsystem`: The subsystem identifier for the `Logger` instance
- `userAgentConfiguration`: Optional User-Agent configuration
- `responseDecoderProvider`: Optional global JSON decoder provider for responses (overrides per-request decoding when enabled)

**Example:**
```swift
// Fixed base URL
let manager = NetworkManager(baseURL: { URL(string: "https://api.example.com")! })

// Dynamic base URL (e.g. from settings)
let manager = NetworkManager(baseURL: { AppSettings.shared.apiBaseURL })

// Convenience: fixed base URL (wraps URL in a closure)
let manager = NetworkManager(baseURL: URL(string: "https://api.example.com")!)
```

### Properties

#### `baseURL: () -> URL`
Closure that provides the base URL; call `baseURL()` to get the current base URL. Each request invokes this closure, so the URL can change between requests without race conditions.

#### `tokenRefresher: TokenRefreshProvider?`
Optional token refresher to handle authentication token renewal. When set, automatically refreshes tokens on 401 responses.

#### `userAgentConfiguration: UserAgentConfiguration?`
User-Agent configuration. If set, automatically adds User-Agent header to all requests.

#### `responseDecoderProvider: (() -> JSONDecoder)?`
Optional global decoder provider for JSON responses. If set, it can override per-request decoding.

### Methods

#### `send<T: NetworkRequest>(_ request: T, accessToken: (() -> String?)?) async throws -> T.Response`

Sends a network request and decodes the response.

**Parameters:**
- `request`: The network request to send
- `accessToken`: Optional closure that returns the access token for authentication

**Returns:** Decoded response of type `T.Response`

**Throws:** Errors encountered during the request or decoding

**Example:**
```swift
let response = try await manager.send(
    SignInRequest(email: "user@example.com", password: "password"),
    accessToken: { TokenStore.shared.accessToken }
)
```

---

## NetworkRequest

Protocol representing a network request. Conforming types define the request path, method, headers, parameters, and response type.

### Required Properties

#### `associatedtype Response: Decodable`
The expected response type, must conform to `Decodable`.

#### `var path: String { get }`
The path component appended to the base URL. By default the path is treated as **not** percent-encoded: it is normalized (leading/trailing slashes trimmed, `//` collapsed, `..` rejected) and joined to the base URL via `appendingPathComponent`. To embed already-encoded reserved characters in the path (for example `%2F` in a GitLab `repository/files/:file_path`), set `pathIsPercentEncoded` to `true` — see below.

#### `var method: HTTPMethod { get }`
HTTP method for the request.

### Optional Properties (with defaults)

#### `var pathIsPercentEncoded: Bool { get }`
Whether `path` is already percent-encoded and must be used verbatim. Defaults to `false`. Added in **1.6.1**.

When `false` (default), the URL is built with `appendingPathComponent`, which re-encodes `%` — so a path segment like `a%2Fb` becomes `a%252Fb`. That is correct for plain paths but breaks endpoints that expect a pre-encoded segment.

When `true`, the path is joined via `percentEncodedPath`, preserving reserved characters such as `%2F` exactly. Use this for APIs that take an encoded resource identifier in the path:

```swift
struct ReadFileRequest: NetworkRequest {
    typealias Response = FileBlob
    let projectID: Int
    let encodedFilePath: String   // e.g. "src%2FApp%2Fmain.swift"

    var path: String { "/api/v4/projects/\(projectID)/repository/files/\(encodedFilePath)" }
    var pathIsPercentEncoded: Bool { true }
    var queryParameters: [String: String]? { ["ref": "main"] }
}
```

Existing requests are unaffected: omit the property to keep the legacy behavior.

#### `var headers: [String: String]? { get }`
Optional HTTP headers to include in the request. Defaults to `nil`.

#### `var queryParameters: [String: String]? { get }`
Optional query parameters appended to the URL. Defaults to `nil`.

#### `var contentType: String { get }`
Content-Type header for the request. Defaults to `"application/json"`.

#### `var body: RequestBody? { get }`
Optional body sent with the request, supporting multiple encodings. Defaults to `nil`.

#### `var multipartData: MultipartFormData? { get }`
Optional multipart form data for upload requests. Defaults to `nil`.

#### `var progress: NetworkProgress? { get }`
Optional progress observer for upload/download progress. Defaults to `nil`.

#### `var retryPolicy: RetryPolicy { get }`
Retry policy to apply for this request. Defaults to `RetryPolicy()`.

#### `var errorDecoder: ((Data) -> Error?)? { get }`
Optional custom error decoder to extract server-side error responses. Defaults to `nil`.

#### `var allowsRetry: Bool { get }`
Should the request allow retries and token refresh on 401 Unauthorized? Defaults to `true`.

#### `var emptyResponseHandler: ((HTTPURLResponse) throws -> Response)? { get }`
Optional handler used when the server returns an empty body. Defaults to `nil`.

When the endpoint returns a successful status with zero-length payload, `NetworkRequest` invokes this handler instead of trying to decode JSON. If you leave it `nil`, `decodeResponse` throws `NetworkError.emptyResponse`.

**Choosing the right approach for empty responses:**

1. **Use `EmptyResponse`** (recommended for simple success cases):
   ```swift
   struct DeleteRequest: NetworkRequest {
       typealias Response = EmptyResponse
       // emptyResponseHandler is automatically provided
   }
   ```
   Best for endpoints that return 204 No Content or empty bodies where you only need to confirm success. The default implementation ignores any payload and returns `EmptyResponse()`.

2. **Use `StatusCodeResponse`** (when you need HTTP metadata):
   ```swift
   struct UpdateRequest: NetworkRequest {
       typealias Response = StatusCodeResponse
       // emptyResponseHandler automatically extracts status code and headers
   }
   ```
   Best when you need to inspect the HTTP status code or headers from the response. The default implementation copies status code and headers from `HTTPURLResponse`.

3. **Provide custom `emptyResponseHandler`** (for advanced cases):
   ```swift
   struct CustomRequest: NetworkRequest {
       typealias Response = MyCustomResponse
       
       var emptyResponseHandler: ((HTTPURLResponse) throws -> MyCustomResponse)? {
           { response in
               MyCustomResponse(
                   status: response.statusCode,
                   customHeader: response.value(forHTTPHeaderField: "X-Custom")
               )
           }
       }
   }
   ```
   Only needed when you must synthesize a custom response type from headers, status code, or other metadata that accompanies the empty payload.

#### `var jsonDecoder: JSONDecoder { get }`
Provides a decoder instance for JSON responses. Defaults to `JSONDecoder()`.

#### `var jsonEncoder: JSONEncoder { get }`
Provides an encoder instance for JSON request bodies. Defaults to `JSONEncoder()`.

#### `var allowsResponseDecoderOverride: Bool { get }`
Whether `NetworkManager` is allowed to override decoding for this request when a global decoder is configured. Defaults to `true`.

### Methods

#### `func decodeResponse(data: Data, response: URLResponse) throws -> Response`

Decodes the raw response into the associated response type.

**Parameters:**
- `data`: The response data
- `response`: The URL response

**Returns:** Decoded response of type `Response`

**Throws:** Decoding errors

**Default Implementation:** Handles JSON decoding and empty-response fallbacks.

---

## HTTPMethod

Enum representing HTTP methods supported by the network layer.

```swift
public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
    case options = "OPTIONS"
    case trace = "TRACE"
    case connect = "CONNECT"
}
```

---

## RequestBody

Represents a request body for a network request, supporting various types.

### Initializers

#### `init(encodable: Encodable, contentType: String = "application/json")`

Creates a request body from an encodable object (typically for JSON).

**Parameters:**
- `encodable`: The encodable object to encode
- `contentType`: The content type (defaults to `"application/json"`)

#### `init(data: Data, contentType: String)`

Creates a request body from raw data.

**Parameters:**
- `data`: The raw data
- `contentType`: The content type

#### `init(stream: InputStream, contentType: String)`

Creates a request body from an input stream (for large uploads).

**Parameters:**
- `stream`: The input stream
- `contentType`: The content type

#### `init(formURLEncoded parameters: [String: String])`

Creates a form URL encoded request body.

**Parameters:**
- `parameters`: Key-value pairs for form URL encoded data

**Content Type:** Automatically set to `"application/x-www-form-urlencoded"`

### Content Types

The `RequestBody` supports the following content types:

- `.encodable(Encodable)` - JSON-encodable object
- `.raw(Data)` - Raw binary or pre-encoded data
- `.stream(InputStream)` - Stream for large data uploads
- `.formURLEncoded([String: String])` - Key-value pairs for form URL encoded data

---

## MultipartFormData

Represents multipart form data for file uploads.

### Properties

#### `boundary: String`
Unique boundary string used to separate parts. Automatically generated as UUID.

#### `parts: [Part]`
Array of parts included in the multipart form.

### Methods

#### `mutating func addPart(name: String, data: Data, mimeType: String, filename: String? = nil)`

Adds a new part to the multipart form data.

**Parameters:**
- `name`: Form field name
- `data`: Data content
- `mimeType`: MIME type string
- `filename`: Optional filename

#### `func encodedData() -> Data?`

Encodes the multipart form data into a Data object suitable for HTTP body. Uses safe UTF-8 encoding and escapes quotes/backslashes in name and filename per RFC 2183.

**Returns:** Encoded Data representing the multipart form, or `nil` if any header string fails UTF-8 encoding. When used by `NetworkManager`, `nil` results in `NetworkError.invalidMultipartEncoding`.

### Part Structure

```swift
public struct Part {
    public let name: String
    public let filename: String?
    public let data: Data
    public let mimeType: String
}
```

---

## RetryPolicy

Defines the retry behavior for network requests.

### Properties

#### `maxRetryCount: Int`
Maximum number of retry attempts.

#### `delay: TimeInterval`
Delay in seconds before retrying a request.

#### `shouldRetry: (Error) -> Bool`
Closure to determine if a request should be retried based on the encountered error.

### Initialization

```swift
public init(
    maxRetryCount: Int = 0,
    delay: TimeInterval = 1.0,
    shouldRetry: @escaping (Error) -> Bool = { /* default implementation */ }
)
```

**Default Behavior:**
- Does not retry on `NetworkError.unauthorized`
- Does not retry on `URLError.userAuthenticationRequired`
- Does not retry on errors conforming to `NonRetriableError` (e.g. business-level or user-presentable errors)
- Retries on other errors

---

## NetworkProgress

Observable object to track progress of network uploads or downloads.

### Properties

#### `@Published var fractionCompleted: Double`
Fraction of task completed, ranging from 0.0 to 1.0.

### Usage

```swift
@MainActor
class UploadViewModel: ObservableObject {
    @Published var uploadProgress: Double = 0.0
    
    func uploadFile(_ data: Data) async throws {
        let progress = NetworkProgress()
        progress.$fractionCompleted
            .assign(to: &$uploadProgress)
        
        // Use progress in request
        struct UploadRequest: NetworkRequest {
            var progress: NetworkProgress? { progress }
            // ...
        }
    }
}
```

---

## TokenRefreshProvider

Protocol for providing token refresh functionality.

### Methods

#### `func refreshTokenIfNeeded() async throws`

Refreshes authentication token if needed. This method is called automatically when a 401 Unauthorized response is received.

**Example:**
```swift
class TokenManager: TokenRefreshProvider {
    func refreshTokenIfNeeded() async throws {
        let refreshRequest = RefreshTokenRequest(
            refreshToken: TokenStore.shared.refreshToken
        )
        let response = try await networkManager.send(refreshRequest, accessToken: nil)
        TokenStore.shared.accessToken = response.accessToken
    }
}
```

---

## Streaming (NDJSON / SSE)

> Available since **1.6.0**. Chunked body (`chunks`, `dataStream(for:)`) added in **1.7.0**.

`send(_:accessToken:)` is designed for endpoints that return a complete `Decodable` body. For endpoints that emit data incrementally — newline-delimited JSON, Server-Sent Events, chunked log/inference streams — use `stream(_:accessToken:)`. The streaming entry point reuses the **exact same** request-construction pipeline (headers, `Authorization`, `User-Agent`, body, base URL), so app-level code never has to build a `URLRequest` by hand and risk dropping required headers like `X-Device-ID` or custom auth.

### NetworkStreaming protocol

```swift
public protocol NetworkStreaming: AnyObject {
    func stream<T: NetworkRequest>(
        _ request: T,
        accessToken: (() -> String?)?
    ) async throws -> StreamingResponse
}
```

`NetworkManager` conforms to both `NetworkManaging` and `NetworkStreaming`. Existing mocks of `NetworkManaging` are unaffected.

### StreamingResponse

```swift
public struct StreamingResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]

    /// Primary body since 1.7.0 — coalesced `Data` blocks (≈16 KiB).
    public let chunks: AsyncThrowingStream<Data, Error>

    /// Deprecated since 1.7.0 — computed wrapper over `chunks`. Removed in 2.0.0.
    @available(*, deprecated, message: "Use `chunks`, `lines()` or `ndjson(as:)`. Removed in 2.0.0.")
    public var bytes: AsyncThrowingStream<UInt8, Error> { get }

    /// Primary initializer since 1.7.0.
    public init(statusCode: Int, headers: [String: String], chunks: AsyncThrowingStream<Data, Error>)

    /// Deprecated since 1.7.0 — use `init(statusCode:headers:chunks:)`. Removed in 2.0.0.
    @available(*, deprecated, message: "Use init(statusCode:headers:chunks:). Removed in 2.0.0.")
    public init(statusCode: Int, headers: [String: String], bytes: AsyncThrowingStream<UInt8, Error>)

    public func lines() -> AsyncThrowingStream<String, Error>
    public func ndjson<Item: Decodable & Sendable>(
        as itemType: Item.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) -> AsyncThrowingStream<Item, Error>
}
```

- `chunks` — **(since 1.7.0, primary)** raw body as `Data` blocks (≈16 KiB each), in arrival order. **Chunk boundaries are not semantic**: a JSON object, NDJSON line or even a single UTF-8 character may be split across two chunks. Reassemble before decoding (or use `lines()` / `ndjson(as:)`, which do this for you).
- `bytes` — **(deprecated since 1.7.0, removed in 2.0.0)** raw octet stream, one `UInt8` per element. Now a computed wrapper that flattens `chunks`. Prefer `chunks`.
- `lines()` — UTF-8 lines split on `\n`, trailing `\r` trimmed (CRLF-aware), blank lines skipped. Reassembles UTF-8 sequences split across chunk boundaries before decoding each line. Signature and semantics unchanged in 1.7.0 — now parses over `Data` chunks (transparent speed-up).
- `ndjson(as:decoder:)` — one `Decodable` record per non-empty line. A bad line throws and finishes the stream. Signature and semantics unchanged in 1.7.0.

Cancellation propagates automatically: breaking out of iteration or cancelling the surrounding `Task` cancels the underlying network task.

> **Buffering / backpressure.** The underlying stream uses `.unbounded` buffering — bytes are never dropped, but there is **no backpressure** onto the server. If a consumer falls behind a fast producer, chunks accumulate in memory. Consume promptly (or break out of the loop) for very large or unbounded streams.

### URLSessionStreamingProtocol

```swift
public protocol URLSessionStreamingProtocol: Sendable {
    /// Preferred since 1.7.0. Returns coalesced `Data` chunks.
    func dataStream(for request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse)

    /// Deprecated since 1.7.0 — use `dataStream(for:)`. Removed in 2.0.0.
    @available(*, deprecated, message: "Use dataStream(for:). Removed in 2.0.0.")
    func byteStream(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse)
}
```

`URLSession` conforms by default (bridges `URLSession.bytes(for:)` into a fully `Sendable` chunk stream).

The protocol extension provides **mutually-derived default implementations**: `dataStream(for:)` can be derived from `byteStream(for:)` and vice versa. A conformer (custom session or mock) therefore only needs to implement **at least one** of them — implement `dataStream(for:)` for the recommended path. Do not omit both, or the defaults will recurse.

### Behaviour summary

| Concern | `send(_:)` | `stream(_:)` |
|---|---|---|
| Headers, body, auth | `buildURLRequest` | `buildURLRequest` (same path) |
| 401 → token refresh + retry | once, when `allowsRetry == true` | once, before any body byte is emitted |
| Mid-stream 401 | n/a | not retried (body has already started) |
| Non-2xx error | `HTTPError` / `errorDecoder` | drain ≤1 MiB, then `HTTPError` / `errorDecoder` |
| Retry policy (`RetryPolicy`) | applied | not applied (streams cannot be replayed deterministically) |
| Progress (`NetworkProgress`) | applied | not applied |

### StreamingError

```swift
public enum StreamingError: Error, Equatable {
    case invalidResponse                 // response was not an HTTPURLResponse
    case errorPayloadTooLarge(limitBytes: Int)  // non-2xx body exceeded 1 MiB cap
}
```

### Example: NDJSON search

```swift
struct PlayerSearchRequest: NetworkRequest {
    typealias Response = EmptyResponse  // unused for streaming
    var path: String { "/api/v1/players/search" }
    var method: HTTPMethod { .get }
    var queryParameters: [String: String]? { ["q": query, "stream": "true"] }
    var headers: [String: String]? { DeviceHeaders.current() }
    let query: String
}

let response = try await manager.stream(
    PlayerSearchRequest(query: "Bobr"),
    accessToken: { TokenStore.shared.accessToken }
)

for try await item in response.ndjson(as: SearchEvent.self) {
    handle(item)            // render incrementally as items arrive
    if case .end = item { break }
}
```

### Example: Server-Sent Events

```swift
let response = try await manager.stream(MyEventsRequest(), accessToken: nil)
for try await line in response.lines() {
    guard line.hasPrefix("data:") else { continue }
    let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
    process(payload)
}
```

### Example: raw chunks (since 1.7.0)

```swift
let response = try await manager.stream(MyDownloadRequest(), accessToken: nil)

var buffer = Data()
for try await chunk in response.chunks {     // each chunk ≈16 KiB
    buffer.append(chunk)                      // boundaries are not semantic — accumulate
}
// `buffer` now holds the full body; parse it however you like.
```

### Example: custom mock session

```swift
// Implement at least one of dataStream(for:) / byteStream(for:).
// dataStream(for:) is the recommended path since 1.7.0.
struct MockStreamingSession: URLSessionStreamingProtocol {
    let payload: Data
    let status: Int

    func dataStream(for request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(payload)
            continuation.finish()
        }
        return (stream, response)
    }
    // byteStream(for:) is supplied by the protocol's default implementation.
}
```

---

## Error Types

### NonRetriableError

Protocol for errors that should not be retried by the default `RetryPolicy`. Conform your business-level or user-presentable error types to this protocol instead of relying on type name checks.

```swift
public protocol NonRetriableError: Error {}
```

### NetworkError

Errors that can occur during network operations.

```swift
public enum NetworkError: Error {
    case invalidURL              // URL could not be constructed (e.g. path contains "..")
    case invalidMultipartEncoding // Multipart form data failed to encode (e.g. non-UTF-8 header values)
    case emptyResponse           // Response data was empty
    case unauthorized            // Unauthorized access, typically HTTP 401
    case invalidResponse     // Response was missing or of an unexpected type
    case conflictingBodyTypes // Both body and multipartData are set
}
```

### HTTPError

Generic HTTP error carrying status code and payload for diagnostics.

```swift
public struct HTTPError: LocalizedError {
    public let statusCode: Int
    public let data: Data
    public let headers: [String: String]
    
    public var errorDescription: String? {
        "Request failed with status code \(statusCode)"
    }
}
```

---

## Response Types

### StatusCodeResponse

Convenience response that only exposes the HTTP status code and headers.

```swift
public struct StatusCodeResponse: Decodable, Equatable {
    public let statusCode: Int
    public let headers: [String: String]
}
```

Use this response when success is conveyed solely through the HTTP metadata. The default `emptyResponseHandler` for `Response == StatusCodeResponse` copies the status code and headers from the empty `HTTPURLResponse`, so you get those values without decoding a body.

### EmptyResponse

Represents an empty payload. Useful for endpoints that only signal success via status code.

```swift
public struct EmptyResponse: Decodable, Equatable {
    public init() {}
}
```

`EmptyResponse` is handy for endpoints that return 204/empty bodies. The request's default `decodeResponse` returns `EmptyResponse()` immediately and ignores any server payload, so you can treat the response type as a void success marker.

---

## UserAgentConfiguration

Configuration for User-Agent header generation.

### Properties

- `appName: String` - Application name
- `appVersion: String` - Application version
- `bundleIdentifier: String` - Bundle identifier
- `buildNumber: String` - Build number
- `osVersion: String` - iOS/OS version
- `networkVersion: String` - EKNetwork framework version

### Initialization

```swift
public init(
    appName: String? = nil,
    appVersion: String? = nil,
    bundleIdentifier: String? = nil,
    buildNumber: String? = nil,
    osVersion: String? = nil,
    networkVersion: String? = nil
)
```

All parameters are optional and default to values from `Bundle.main` or system defaults.

### Methods

#### `func generateUserAgentString() -> String`

Generates the User-Agent string in the format:
`AppName/Version (BundleID; build:BuildNumber; Platform OSVersion) EKNetwork/Version`

---

## Protocol Abstractions

### NetworkManaging

Protocol abstraction for NetworkManager to allow mocking and dependency injection.

```swift
public protocol NetworkManaging {
    var tokenRefresher: TokenRefreshProvider? { get set }
    func send<T: NetworkRequest>(_ request: T, accessToken: (() -> String?)?) async throws -> T.Response
}
```

### URLSessionProtocol

Protocol abstraction for URLSession to allow mocking and dependency injection.

```swift
public protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
```

`URLSession` conforms to this protocol by default.

---

## 🇷🇺 Русская документация

Полная русскоязычная документация API доступна в отдельном файле:

- 📚 **[API_RU.md](API_RU.md)** - Полный справочник API на русском языке

---
