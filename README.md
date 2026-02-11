<div align="center">

# 🌐 EKNetwork

**A modern, type-safe HTTP networking library for Swift**

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2018%2B%20%7C%20macOS%2015%2B-lightgrey.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/emvakar/EKNetwork/actions/workflows/swift.yml/badge.svg)](https://github.com/emvakar/EKNetwork/actions/workflows/swift.yml)
[![Tests](https://img.shields.io/badge/Tests-156%20passed-brightgreen.svg)](https://github.com/emvakar/EKNetwork/actions)
[![Coverage](https://img.shields.io/badge/Coverage-99.13%25-brightgreen.svg)](https://github.com/emvakar/EKNetwork/actions)

*A lightweight, type-safe HTTP networking library for Swift applications*

[Features](#-features) • [Installation](#-installation) • [Quick Start](#-quick-start) • [Documentation](#-documentation) • [API Reference](#-api-reference) • [Contributing](#-contributing) • [Support](#-support-project) • [Structure](#-project-structure)

[English](#) | [Русский](README_RU.md)

</div>

---

## ✨ Why EKNetwork?

EKNetwork is a modern networking library that combines ease of use with powerful features. It's designed for developers who value type safety, clean code, and modern Swift practices.

### 🎯 Key Features

- **🚀 Type-Safe API** — Full type safety at compile time, no runtime errors
- **⚡ Async/Await** — Native support for modern Swift concurrency without callback hell
- **🔄 Automatic Retry** — Flexible retry policy for each request
- **🔐 Token Refresh** — Automatic token refresh on 401 errors
- **📊 Progress Tracking** — Track upload and download progress with SwiftUI support
- **🎨 Flexible Configuration** — Customize JSON encoding/decoding per request
- **🧪 Testable** — Protocols for easy mocking and testing
- **📦 Zero Dependencies** — No external dependencies, only Swift standard library
- **🛡️ Production Ready** — Tested, optimized, and ready for production use

### 💎 What Makes EKNetwork Special?

#### 🎨 Declarative Approach
Describe requests as Swift types — the compiler will verify your code:

```swift
struct SignInRequest: NetworkRequest {
    struct Response: Decodable {
        let token: String
        let user: User
    }
    // ...
}
```

#### 🔧 Composition and Reusability
Easily combine different request types, create base classes for common patterns:

```swift
protocol AuthenticatedRequest: NetworkRequest {
    // Common logic for authenticated requests
}
```

#### 🛡️ Predictable Error Handling
Clear error hierarchy with custom error handling:

```swift
do {
    let response = try await manager.send(request)
} catch let error as HTTPError {
    // Handle HTTP errors
} catch NetworkError.unauthorized {
    // Handle authorization
}
```

#### ⚡ Minimal Boilerplate
Write less code, do more. One request = one structure:

```swift
struct GetUserRequest: NetworkRequest {
    typealias Response = User
    var path: String { "/users/\(id)" }
    var method: HTTPMethod { .get }
    let id: Int
}
```

#### 🧪 Full Test Coverage
115 tests cover all major use cases, including edge cases. Code coverage is 99.42%.

---

## 📦 Installation

EKNetwork supports multiple installation methods. Choose the one that best fits your project.

### Swift Package Manager (Recommended)

#### Using Package.swift

Add EKNetwork to your project dependencies in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/emvakar/EKNetwork.git", from: "1.4.2")
]
```

Then add the product to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "EKNetwork", package: "EKNetwork")
    ]
)
```

#### Using Xcode

1. In Xcode, select **File** → **Add Packages...**
2. Enter the repository URL: `https://github.com/emvakar/EKNetwork.git`
3. Select **Up to Next Major Version** with `1.4.2`
4. Click **Add Package**
5. Select the `EKNetwork` product and add it to your target

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/emvakar/EKNetwork.git
   cd EKNetwork
   ```

2. Open `Package.swift` in Xcode:
   ```bash
   open Package.swift
   ```

3. Build the framework:
   - Select the `EKNetwork` scheme
   - Build (⌘B)

4. Drag the built framework into your project:
   - Find the framework in `DerivedData` or build products
   - Drag it into your project's **Frameworks** folder
   - Make sure **Copy items if needed** is checked

### Requirements

- **Swift**: 6.0+
- **iOS**: 18.0+
- **macOS**: 15.0+
- **Xcode**: 16.0+ (for Swift 6.0 support)

---

## 🚀 Quick Start

### 1. Create a Request

```swift
import EKNetwork

struct SignInRequest: NetworkRequest {
    struct Response: Decodable {
        let token: String
        let user: User
    }
    
    struct User: Decodable {
        let id: Int
        let email: String
        let name: String
    }

    let email: String
    let password: String

    var path: String { "/api/v1/auth/sign-in" }
    var method: HTTPMethod { .post }

    var body: RequestBody? {
        RequestBody(encodable: [
            "email": email,
            "password": password
        ])
    }
}
```

### 2. Send the Request

```swift
let manager = NetworkManager(
    baseURL: { URL(string: "https://api.example.com")! }
)

let response = try await manager.send(
    SignInRequest(
        email: "user@example.com",
        password: "securepassword"
    ),
    accessToken: { TokenStore.shared.accessToken }
)

print("Token: \(response.token)")
print("User: \(response.user.name)")
```

**That's it!** Just a few lines of code for a full-featured network request with type safety and error handling.

---

## 📚 Documentation

### 📖 API Reference

For complete API documentation, see [API.md](API.md). The API reference includes:
- Complete method and property documentation
- Parameter descriptions
- Usage examples
- Error handling details
- Protocol conformances

### Basic Examples

#### Requests with Query Parameters

```swift
struct SearchRequest: NetworkRequest {
    struct Response: Decodable {
        let results: [SearchResult]
        let total: Int
    }
    
    let query: String
    let page: Int
    
    var path: String { "/api/search" }
    var method: HTTPMethod { .get }
    
    var queryParameters: [String: String]? {
        ["q": query, "page": "\(page)", "limit": "20"]
    }
}

let response = try await manager.send(
    SearchRequest(query: "Swift", page: 1),
    accessToken: nil
)
```

#### File Upload (Multipart)

```swift
struct UploadAvatarRequest: NetworkRequest {
    typealias Response = StatusCodeResponse
    
    let imageData: Data
    
    var path: String { "/api/user/avatar" }
    var method: HTTPMethod { .post }
    
    var multipartData: MultipartFormData? {
        var data = MultipartFormData()
        data.addPart(
            name: "avatar",
            data: imageData,
            mimeType: "image/jpeg",
            filename: "avatar.jpg"
        )
        return data
    }
}

let response = try await manager.send(
    UploadAvatarRequest(imageData: imageData),
    accessToken: tokenProvider
)
```

#### Progress Tracking

```swift
@MainActor
class UploadViewModel: ObservableObject {
    @Published var uploadProgress: Double = 0.0
    
    func uploadFile(_ data: Data) async throws {
        let progress = NetworkProgress()
        
        // Bind progress to UI
        progress.$fractionCompleted
            .assign(to: &$uploadProgress)
        
        struct UploadRequest: NetworkRequest {
            typealias Response = StatusCodeResponse
            var path: String { "/api/upload" }
            var method: HTTPMethod { .post }
            var progress: NetworkProgress? { progress }
            var multipartData: MultipartFormData? {
                var data = MultipartFormData()
                data.addPart(name: "file", data: fileData, mimeType: "application/octet-stream")
                return data
            }
        }
        
        let manager = NetworkManager(baseURL: { baseURL })
        _ = try await manager.send(UploadRequest(), accessToken: nil)
    }
}
```

#### Retry Policy

```swift
struct CriticalRequest: NetworkRequest {
    typealias Response = CriticalData
    
    var path: String { "/api/critical" }
    var method: HTTPMethod { .get }
    
    var retryPolicy: RetryPolicy {
        RetryPolicy(
            maxRetryCount: 3,
            delay: 2.0
        ) { error in
            // Retry only on network errors
            if let urlError = error as? URLError {
                return urlError.code == .timedOut || 
                       urlError.code == .networkConnectionLost
            }
            return false
        }
    }
}
```

#### Automatic Token Refresh

```swift
class TokenManager: TokenRefreshProvider {
    func refreshTokenIfNeeded() async throws {
        // Your token refresh logic
        let refreshRequest = RefreshTokenRequest(
            refreshToken: TokenStore.shared.refreshToken
        )
        let response = try await networkManager.send(refreshRequest, accessToken: nil)
        TokenStore.shared.accessToken = response.accessToken
    }
}

let manager = NetworkManager(baseURL: { baseURL })
manager.tokenRefresher = TokenManager()

// On 401, token will automatically refresh and request will retry
let response = try await manager.send(
    ProtectedRequest(),
    accessToken: { TokenStore.shared.accessToken }
)
```

#### Custom Error Handling

```swift
struct APIRequest: NetworkRequest {
    typealias Response = APIResponse
    
    var path: String { "/api/data" }
    var method: HTTPMethod { .get }
    
    var errorDecoder: ((Data) -> Error?)? {
        { data in
            // Decode custom error from server
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                return apiError
            }
            return nil
        }
    }
}

struct APIError: Decodable, Error {
    let code: String
    let message: String
}
```

### Advanced Features

#### Custom JSON Encoders/Decoders

```swift
struct DateRequest: NetworkRequest {
    struct Body: Encodable {
        let timestamp: Date
        let event: String
    }
    
    struct Response: Decodable {
        let id: String
        let createdAt: Date
    }
    
    var path: String { "/api/events" }
    var method: HTTPMethod { .post }
    
    var body: RequestBody? {
        RequestBody(encodable: Body(timestamp: Date(), event: "test"))
    }
    
    var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
    
    var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
```

#### Global Response Decoder (Optional)

If you want a single decoding strategy across all requests (for example, flexible date parsing), you can provide a global decoder when creating `NetworkManager`.

```swift
let network = NetworkManager(
    baseURL: URL(string: "https://api.example.com")!,
    responseDecoderProvider: {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
)
```

By default, the global decoder is used only when the request allows it.
To opt out for specific requests that rely on custom `decodeResponse`, set:

```swift
var allowsResponseDecoderOverride: Bool { false }
```

Example: flexible date decoding (string or unix seconds):

```swift
let network = NetworkManager(
    baseURL: URL(string: "https://api.example.com")!,
    responseDecoderProvider: {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            if let string = try? container.decode(String.self) {
                if let date = ISO8601DateFormatter().date(from: string) {
                    return date
                }
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                df.dateFormat = "yyyy-MM-dd"
                if let date = df.date(from: string) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
        }
        return decoder
    }
)
```

#### Form URL Encoded

```swift
struct LoginRequest: NetworkRequest {
    struct Response: Decodable {
        let token: String
    }
    
    let username: String
    let password: String
    
    var path: String { "/login" }
    var method: HTTPMethod { .post }
    
    var body: RequestBody? {
        RequestBody(formURLEncoded: [
            "username": username,
            "password": password
        ])
    }
}
```

#### Raw Data Body

```swift
struct BinaryUploadRequest: NetworkRequest {
    typealias Response = UploadResponse
    
    let binaryData: Data
    
    var path: String { "/api/upload/binary" }
    var method: HTTPMethod { .post }
    
    var body: RequestBody? {
        RequestBody(data: binaryData, contentType: "application/octet-stream")
    }
}
```

#### Dynamic Base URL

```swift
// Base URL is resolved per request via closure — no race conditions
var currentBase = URL(string: "https://api.staging.example.com")!
let manager = NetworkManager(baseURL: { currentBase })

// Switch to production: update the value your closure captures
currentBase = URL(string: "https://api.example.com")!
// All subsequent requests will use the new URL

// Or read from config/environment
let manager = NetworkManager(baseURL: { AppConfig.shared.apiBaseURL })
```

#### User-Agent Configuration

```swift
let userAgentConfig = UserAgentConfiguration(
    appName: "MyApp",
    appVersion: "2.0.0",
    bundleIdentifier: "com.example.myapp",
    buildNumber: "123",
    osVersion: UIDevice.current.systemVersion
)

let manager = NetworkManager(
    baseURL: { baseURL },
    userAgentConfiguration: userAgentConfig
)
// User-Agent will be automatically added to all requests
```

---

## 🎓 Best Practices

### 1. Organizing Requests

Group requests by functionality for better code organization:

```swift
enum AuthRequests {
    struct SignIn: NetworkRequest {
        struct Response: Decodable { let token: String }
        let email: String
        let password: String
        var path: String { "/auth/sign-in" }
        var method: HTTPMethod { .post }
        // ...
    }
    
    struct SignOut: NetworkRequest {
        typealias Response = EmptyResponse
        var path: String { "/auth/sign-out" }
        var method: HTTPMethod { .post }
    }
    
    struct RefreshToken: NetworkRequest {
        struct Response: Decodable { let accessToken: String }
        let refreshToken: String
        var path: String { "/auth/refresh" }
        var method: HTTPMethod { .post }
        // ...
    }
}

enum UserRequests {
    struct GetProfile: NetworkRequest {
        typealias Response = UserProfile
        var path: String { "/user/profile" }
        var method: HTTPMethod { .get }
    }
    
    struct UpdateProfile: NetworkRequest {
        typealias Response = UserProfile
        let name: String
        var path: String { "/user/profile" }
        var method: HTTPMethod { .put }
        // ...
    }
}
```

### 2. Centralized NetworkManager

Create a single API access point:

```swift
class APIClient {
    static let shared = APIClient()
    
    private let manager: NetworkManager
    
    private init() {
        let baseURL = URL(string: "https://api.example.com")!
        manager = NetworkManager(
            baseURL: { baseURL },
            userAgentConfiguration: UserAgentConfiguration(
                appName: Bundle.main.appName,
                appVersion: Bundle.main.appVersion,
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
                buildNumber: Bundle.main.buildNumber,
                osVersion: UIDevice.current.systemVersion
            )
        )
        manager.tokenRefresher = TokenManager()
    }
    
    func send<T: NetworkRequest>(_ request: T) async throws -> T.Response {
        try await manager.send(request, accessToken: {
            TokenStore.shared.accessToken
        })
    }
}

// Usage
let profile = try await APIClient.shared.send(UserRequests.GetProfile())
```

### 3. Error Handling

Use error hierarchy for proper handling:

```swift
func handleRequest<T: NetworkRequest>(_ request: T) async {
    do {
        let response = try await manager.send(request, accessToken: tokenProvider)
        // Handle successful response
        await handleSuccess(response)
    } catch let error as HTTPError {
        switch error.statusCode {
        case 400:
            await handleBadRequest(error)
        case 401:
            await handleUnauthorized()
        case 404:
            await handleNotFound()
        case 500...599:
            await handleServerError(error)
        default:
            await handleUnknownError(error)
        }
    } catch NetworkError.unauthorized {
        await handleUnauthorized()
    } catch NetworkError.invalidURL {
        await handleInvalidURL()
    } catch {
        await handleUnknownError(error)
    }
}
```

### 4. Testing

Use protocols for mocking:

```swift
// Mock URLSession
class MockURLSession: URLSessionProtocol {
    var responseData: Data?
    var response: URLResponse?
    var error: Error?
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = error {
            throw error
        }
        return (
            responseData ?? Data(),
            response ?? HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

// In tests
func testSignIn() async throws {
    let mockSession = MockURLSession()
    mockSession.responseData = try JSONEncoder().encode(
        SignInRequest.Response(token: "test-token", user: testUser)
    )
    
    let manager = NetworkManager(
        baseURL: { URL(string: "https://test.com")! },
        session: mockSession
    )
    
    let response = try await manager.send(
        SignInRequest(email: "test@test.com", password: "password"),
        accessToken: nil
    )
    
    XCTAssertEqual(response.token, "test-token")
}
```

---

## 🧪 Testing

EKNetwork has comprehensive test coverage (115 tests, 99.42% code coverage) and provides protocols for easy testing:

- ✅ All HTTP methods (GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, TRACE, CONNECT)
- ✅ Query parameters
- ✅ Various body types (JSON, Form URL Encoded, Multipart, Raw Data)
- ✅ Retry policy
- ✅ Token refresh
- ✅ Error handling
- ✅ Progress tracking
- ✅ User-Agent configuration
- ✅ Content-Length headers

### Running Tests

Run all tests:

```bash
swift test
```

### Code Coverage

Check code coverage locally:

```bash
./scripts/coverage.sh
```

This will:
1. Run tests with coverage enabled
2. Generate a coverage report
3. Display coverage percentage
4. Check if coverage meets the 98% requirement

Run `./scripts/coverage.sh` for detailed coverage; see script and CI for thresholds.

**Note:** Coverage is automatically checked in CI/CD on every push and pull request.

---

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

### How to Help

- ⭐ **Star the repository** on GitHub — helps the project be more visible
- 🐛 **Report bugs** — create issues with detailed problem descriptions
- 💡 **Suggest features** — share ideas for improving the library
- 📝 **Improve documentation** — help make documentation better
- 🔧 **Submit Pull Requests** — fixes and new features are always welcome
- 💬 **Spread the word** — share with friends and colleagues
- 🐦 **Watch for updates** — watch the repository to stay informed

### Contribution Process

1. Fork the repository
2. Create a branch for your changes (`git checkout -b feature/amazing-feature`)
3. Make changes and add tests
4. Ensure all tests pass (`swift test`)
5. Create a Pull Request with a detailed description of changes

See [CONTRIBUTING.md](CONTRIBUTING.md) for more details.

---

## 💚 Support Project

EKNetwork is an open source project created with love for the Swift community. If the project is useful to you, consider supporting it:

### Ways to Support

- ⭐ **Star on GitHub** — it's free and helps the project
- 🐛 **Report bugs** — help improve quality
- 💡 **Suggest ideas** — share your thoughts on development
- 🔧 **Contribute code** — Pull Requests are always welcome
- 📢 **Spread the word** — share on social media, blogs, conferences
- 💰 **Financial support** — if you want to support development financially, contact the author

### Why Support Matters

- 🚀 Helps the project develop faster
- 🐛 Improves quality and stability
- 📚 Expands documentation and examples
- 🌟 Makes the project more visible in the community
- 💡 Inspires new features and improvements

**Thank you to everyone who supports the project!** 🙏

---

## 📄 License

EKNetwork is available under the MIT license. See [LICENSE](LICENSE) for more information.

---

## 🙏 Acknowledgments

Thank you to all contributors who help improve EKNetwork!

Special thanks to:
- The Swift community for inspiration and feedback
- Everyone who tests the library and reports bugs
- Contributors who improve code and documentation

---

## 📞 Support & Contact

- 💬 **Issues**: [GitHub Issues](https://github.com/emvakar/EKNetwork/issues)
- 📖 **API Reference**: [API.md](API.md) - Complete API documentation
- 📚 **Documentation**: [Full Documentation](https://github.com/emvakar/EKNetwork/wiki)
- 🔒 **Security**: [SECURITY.md](SECURITY.md) for vulnerability reports

---

## 📊 Project Status

- ✅ **Stable**: Ready for production use
- ✅ **Tested**: 21 tests cover major scenarios
- ✅ **Documented**: Complete documentation with examples
- ✅ **Maintained**: Active support and development

## 📁 Project Structure

For developers wishing to contribute, see [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) for project structure understanding.

## 🗺️ Roadmap

For planned improvements and known issues, see [ROADMAP.md](ROADMAP.md).

## 📋 Summary for Potential Clients

For a comprehensive overview of EKNetwork's features, benefits, and use cases, see [SUMMARY.md](SUMMARY.md). This document helps potential users understand:
- Key value propositions
- Feature comparison with alternatives
- Production readiness
- Migration paths
- Getting started guide

---

<div align="center">

**Made with ❤️ for the Swift community**

[⬆ Back to top](#-eknetwork)

[⭐ Star the project if it's useful to you!](#)

</div>

---

## 🇷🇺 Русская документация

Полная русскоязычная документация доступна в отдельных файлах:

- 📖 **[README_RU.md](README_RU.md)** - Полная документация на русском языке
- 📚 **[API_RU.md](API_RU.md)** - Справочник API на русском языке

---
