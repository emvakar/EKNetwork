# EKNetwork

EKNetwork — это лёгкий и расширяемый Swift-фреймворк для декларативных сетевых запросов с поддержкой:
- `async/await` API,
- прогресса загрузки (upload),
- обработки `multipart/form-data`,
- автоматического обновления токенов (refresh token),
- retry-политики и логирования.

## Установка

Добавьте в `Package.swift`:

```swift
.package(url: "https://github.com/your-username/EKNetwork.git", from: "1.0.0")
```

И подключите `EKNetwork` в зависимостях вашей цели.

## Использование

### 1. Опишите запрос

```swift
struct SignInRequest: NetworkRequest {
    struct Response: Decodable {
        let token: String
    }

    let email: String
    let password: String

    var path: String { "/api/v1/auth/signin" }
    var method: HTTPMethod { .post }

    var bodyParameters: [String : Any]? {
        ["email": email, "password": password]
    }
}
```

### 2. Отправьте запрос

```swift
let manager = NetworkManager(baseURL: URL(string: "https://example.com")!)
let result = try await manager.send(SignInRequest(email: "test@example.com", password: "123"))
```

### 3. Прогресс загрузки

```swift
let progress = NetworkProgress()

struct UploadPhoto: NetworkRequest {
    struct Response: Decodable { let url: String }

    var path: String { "/upload" }
    var method: HTTPMethod { .post }
    var multipartData: MultipartFormData? {
        var form = MultipartFormData()
        form.addPart(name: "image", data: imageData, mimeType: "image/jpeg", filename: "photo.jpg")
        return form
    }
    var progress: NetworkProgress? = progress
}
```

Используйте `progress.fractionCompleted` в SwiftUI через `@ObservedObject`.

### 4. Обновление токенов

Реализуйте:

```swift
final class AuthRefresher: TokenRefreshProvider {
    func refreshTokenIfNeeded() async throws {
        // Выполнить запрос обновления refresh токена
    }
}

manager.tokenRefresher = AuthRefresher()
```

### 5. Индивидуальная RetryPolicy

```swift
struct MyRequest: NetworkRequest {
    var retryPolicy: RetryPolicy {
        RetryPolicy(maxRetryCount: 3, delay: 2.0) {
            !($0 is NetworkError)
        }
    }

    // ...
}
```

## Преимущества

- Поддержка всех HTTP-методов
- Простая реализация upload/download с прогрессом
- Расширяемость за счёт протоколов
- Хорошо покрывается моками для тестирования

## Лицензия

MIT
