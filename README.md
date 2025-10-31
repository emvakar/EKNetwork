# EKNetwork

EKNetwork is a tiny, strongly typed HTTP layer for Swift applications that embraces `async/await`, composable requests, and predictable error handling. It focuses on clear request definitions, ergonomic decoding, and first-class support for modern API scenarios such as token refresh, structured retries, multipart uploads, and progress reporting.

---

## Why EKNetwork?

- Declarative `NetworkRequest` protocol with typed responses
- Automatic base URL management and runtime switching
- Request-scoped retry policy and token refresh integration
- Multipart uploads, raw/stream bodies, and URL-encoded forms
- Upload **and** download progress reporting via `NetworkProgress`
- Configurable JSON encoding/decoding per request
- Built-in helpers for empty and status-code-only endpoints
- Lightweight logging with `os.Logger`

---

## Installation

Add EKNetwork to your package dependencies:

```swift
.package(url: "https://github.com/your-username/EKNetwork.git", from: "1.0.0")
```

Then reference the product in the target where you need it:

```swift
.product(name: "EKNetwork", package: "EKNetwork")
```

---

## Quick Start

### 1. Describe a request

```swift
struct SignInRequest: NetworkRequest {
    struct Response: Decodable {
        let token: String
    }

    let email: String
    let password: String

    var path: String { "/api/v1/auth/sign-in" }
    var method: HTTPMethod { .post }

    var body: RequestBody? {
        RequestBody(encodable: ["email": email, "password": password])
    }
}
```

### 2. Send it

```swift
let manager = NetworkManager(baseURL: URL(string: "https://example.com")!)
let response = try await manager.send(SignInRequest(email: "user@example.com",
                                                    password: "letmein"),
                                      accessToken: { TokenStore.shared.accessToken })
print(response.token)
```

If you provide both a manual `Authorization` header and an `accessToken` closure, EKNetwork preserves the header you supplied and skips the automatic `Bearer` injection.

---

## Handling responses without payloads

Some APIs return nothing but a status code. EKNetwork includes helpers for these cases:

```swift
// Only status code + headers
struct PingRequest: NetworkRequest {
    typealias Response = StatusCodeResponse

    var path: String { "/ping" }
    var method: HTTPMethod { .get }
}

// Truly empty body
struct LogoutRequest: NetworkRequest {
    typealias Response = EmptyResponse

    var path: String { "/auth/logout" }
    var method: HTTPMethod { .post }
}
```

Prefer `StatusCodeResponse` when you need to surface headers such as pagination or rate limits, and `EmptyResponse` when success is binary.

Need custom handling? Provide your own fallback:

```swift
struct CustomRequest: NetworkRequest {
    struct Response: Decodable { /* ... */ }
    var path: String { "/custom" }
    var method: HTTPMethod { .get }

    var emptyResponseHandler: ((HTTPURLResponse) throws -> Response)? {
        { response in throw APIError.empty(status: response.statusCode) }
    }
}
```

---

## JSON coding on your terms

Requests and responses can each customize their JSON coders:

```swift
struct AnalyticsRequest: NetworkRequest {
    struct Body: Encodable { let timestamp: Date }
    struct Response: Decodable { /* ... */ }

    var path: String { "/events" }
    var method: HTTPMethod { .post }

    var body: RequestBody? {
        RequestBody(encodable: Body(timestamp: Date()))
    }

    var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
```

Every request owns its encoder/decoder pair, so you can align with backend quirks without global state.

---

## Bodies, headers, and query helpers

- `RequestBody` supports `.encodable`, `.raw(Data)`, `.stream(InputStream)`, and `.formURLEncoded([String: String])`. URL-encoded data is safely percent-escaped by default.
- Supply per-request headers and query parameters directly through `headers` and `queryParameters`.
- For multipart uploads, compose `MultipartFormData` with lightweight `Part` definitions.

---

## Retries, errors, and token refresh

- Use `retryPolicy` to configure per-request retry limits, delays, and retry predicates.
- Plug in a `TokenRefreshProvider` to automatically refresh tokens after a `401` response. Requests opt in via `allowsRetry`.
- Non-success HTTP responses throw `HTTPError`, containing the status code, normalized headers, and raw payload. Swap in `errorDecoder` to map backend error contracts onto domain-specific error types.

---

## Progress tracking

Attach a `NetworkProgress` instance to any request to observe both uploads and downloads:

```swift
let progress = NetworkProgress()

struct UploadAvatar: NetworkRequest {
    typealias Response = StatusCodeResponse
    var path: String { "/profile/avatar" }
    var method: HTTPMethod { .post }
    var progress: NetworkProgress? { progress }
    var multipartData: MultipartFormData? { /* ... */ }
}
```

The `fractionCompleted` property stays on the main actor, ready for SwiftUI bindings or UIKit updates.

---

## Dynamic base URL management

```swift
manager.updateBaseURL(URL(string: "https://api-v2.example.com")!)
print(manager.baseURL) // updated instantly
```

Switch between staging, production, or feature environments without rebuilding the manager.

---

## Testing support

- `NetworkManaging` and `URLSessionProtocol` abstractions enable lightweight mocking.
- The included test suite demonstrates request interception via `URLProtocol`, header verification, and status-only workflows—use it as a template for your own tests.

---

EKNetwork keeps the networking surface small, predictable, and testable while letting you opt into richer behaviours only when needed. Plug it into your modules, shape each request through Swift types, and let the framework take care of the repetitive plumbing. HAPPY networking! 
