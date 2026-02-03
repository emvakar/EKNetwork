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
    loggerSubsystem: String = "com.yourapp.networking",
    userAgentConfiguration: UserAgentConfiguration? = nil
)
```

**Parameters:**
- `baseURL`: Closure that returns the base URL for each request. Use `{ myURL }` for a fixed URL or a closure that reads from config/environment for dynamic base URL (avoids race conditions when switching environments).
- `session`: The `URLSessionProtocol` to use for making requests (defaults to `URLSession.shared`)
- `loggerSubsystem`: The subsystem identifier for the `Logger` instance
- `userAgentConfiguration`: Optional User-Agent configuration

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
The path component appended to the base URL.

#### `var method: HTTPMethod { get }`
HTTP method for the request.

### Optional Properties (with defaults)

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
