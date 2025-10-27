# EKNetwork

**EKNetwork** is a lightweight, extensible Swift framework designed for building type-safe, declarative, and asynchronous HTTP network layers in a clean and maintainable way. It provides powerful abstractions and modern Swift capabilities such as `async/await`, type-safe request models, customizable retry policies, multipart upload support, token refresh integration, and upload/download progress tracking — all with minimal boilerplate.

---

## ✨ Features

- ✅ `async/await` request handling
- ✅ Strongly-typed, declarative `NetworkRequest` protocol
- ✅ Dynamic base URL updates at runtime
- ✅ Multipart form-data uploads (`multipart/form-data`)
- ✅ Upload progress tracking with SwiftUI compatibility
- ✅ Built-in retry policy with per-request customization
- ✅ Automatic `401`-handling via refresh token flow
- ✅ Custom token refresh logic via protocol
- ✅ Rich request body support: `Encodable`, raw data, `InputStream`, `x-www-form-urlencoded`
- ✅ Configurable HTTP headers, query, and path
- ✅ Integrated logging using `os.Logger`
- ✅ Fully documented and testable design

---

## 📦 Installation

Add the following to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/your-username/EKNetwork.git", from: "1.0.0")
```

And include `"EKNetwork"` in your target dependencies.

---

## 🚀 Getting Started

### 1. Define a Request

Conform your request to `NetworkRequest`:

```swift
struct SignInRequest: NetworkRequest {
    struct Response: Decodable {
        let token: String
    }

    let email: String
    let password: String

    var path: String { "/api/v1/auth/signin" }
    var method: HTTPMethod { .post }

    var body: RequestBody? {
        RequestBody(encodable: ["email": email, "password": password])
    }
}
```

You can also use `.raw(Data)`, `.stream(InputStream)`, or `.formURLEncoded([String: String])`.

### 2. Send the Request

```swift
let manager = NetworkManager(baseURL: URL(string: "https://example.com")!)
let response = try await manager.send(SignInRequest(email: "user@example.com", password: "secret"))
```

---

## 📤 Upload with Multipart and Progress

```swift
let progress = NetworkProgress()

struct UploadImageRequest: NetworkRequest {
    struct Response: Decodable { let url: String }

    let imageData: Data
    var progress: NetworkProgress? = nil

    var path: String { "/upload" }
    var method: HTTPMethod { .post }

    var multipartData: MultipartFormData? {
        var form = MultipartFormData()
        form.addPart(name: "file", data: imageData, mimeType: "image/jpeg", filename: "photo.jpg")
        return form
    }
}
```

In SwiftUI:

```swift
ProgressView(value: progress.fractionCompleted)
```

---

## 🔁 Token Refresh Handling

Implement the `TokenRefreshProvider` protocol to support automatic refresh on 401:

```swift
final class MyRefresher: TokenRefreshProvider {
    func refreshTokenIfNeeded() async throws {
        // Send a refresh request, update token storage
    }
}
```

Then configure your `NetworkManager`:

```swift
manager.tokenRefresher = MyRefresher()
```

If a request fails with `401`, the manager will attempt to refresh the token and retry the original request once.

---

## 🔄 Retry Policy

Each request can declare its own retry logic:

```swift
struct MyRequest: NetworkRequest {
    var retryPolicy: RetryPolicy {
        RetryPolicy(maxRetryCount: 3, delay: 2.0) {
            error in !(error is NetworkError)
        }
    }

    // ...
}
```

Global retry behavior is managed per request — including exponential backoff, selective retries, etc.

---

## 🔗 Dynamic Base URL Updates

You can change the base URL at runtime and all subsequent requests will use the updated URL:

```swift
let manager = NetworkManager(baseURL: URL(string: "https://api-v1.example.com")!)

// Make requests with v1 API
let response1 = try await manager.send(SomeRequest())

// Switch to v2 API
manager.updateBaseURL(URL(string: "https://api-v2.example.com")!)

// All new requests now use v2 API
let response2 = try await manager.send(SomeRequest())

// You can also read the current base URL
print(manager.baseURL) // https://api-v2.example.com
```

**Note:** Changes take effect immediately for new requests. Requests that are already in progress will continue using the old base URL.

**Use Cases:**

- Switching between staging and production environments
- A/B testing different API endpoints
- Multi-tenant applications with dynamic API endpoints
- Failover to backup servers

---

## 🧪 Testability

Mock your own `NetworkManager` or `URLProtocol`, or pass fake responses through dependency injection. Each request is strongly typed and isolated.

---

## 🧱 Request Body Types

```swift
RequestBody(encodable: someEncodableStruct)
RequestBody(data: rawData, contentType: "application/json")
RequestBody(stream: inputStream, contentType: "video/mp4")
RequestBody(formURLEncoded: ["key": "value"])
```

---

## 🛠 Advanced Configuration

```swift
let manager = NetworkManager(
    baseURL: URL(string: "https://api.example.com")!,
    tokenRefresher: MyRefresher(),
    session: URLSession(configuration: .default),
    loggerSubsystem: "com.myapp.network"
)
```

---

## 🧩 Extending EKNetwork

- Implement custom loggers
- Add metrics collectors
- Create wrappers for common REST patterns
- Customize JSON encoder/decoder

---

## 📚 Documentation

Full API documentation is available via Xcode DocC. Look for `EKNetwork` in the documentation browser.

---

## 📄 License

EKNetwork is released under the MIT License. See [LICENSE](LICENSE) for details.
