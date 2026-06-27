# 🌐 EKNetwork

**Современная типобезопасная HTTP библиотека для Swift**

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2015%2B%20%7C%20macOS%2015%2B-lightgrey.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-220%20passed-brightgreen.svg)](https://github.com/emvakar/EKNetwork/actions)
[![Coverage](https://img.shields.io/badge/Coverage-99.42%25-brightgreen.svg)](https://github.com/emvakar/EKNetwork/actions)

*Легковесная, типобезопасная библиотека для работы с HTTP в Swift приложениях*

[English](README.md) | [Русский](#)

---

## ✨ Почему EKNetwork?

EKNetwork — это современная библиотека для сетевых запросов, которая сочетает простоту использования с мощными возможностями. Она создана для разработчиков, которые ценят типобезопасность, чистый код и современные практики Swift.

### 🎯 Основные преимущества

- **🚀 Type-Safe API** — Полная типобезопасность на уровне компиляции, никаких runtime ошибок
- **⚡ Async/Await** — Нативная поддержка современного Swift concurrency без callback hell
- **🔄 Автоматический Retry** — Гибкая политика повторных попыток для каждого запроса
- **🔐 Token Refresh** — Автоматическое обновление токенов при 401 ошибках
- **📊 Progress Tracking** — Отслеживание прогресса загрузки и выгрузки с поддержкой SwiftUI
- **🌊 Streaming-ответы** — Полноценная поддержка NDJSON / SSE / chunked transfer через тот же пайплайн `NetworkRequest` (начиная с 1.6.0). См. [API_RU.md](API_RU.md#стриминг-ndjson--sse).
- **🎨 Гибкая конфигурация** — Настройка JSON кодирования/декодирования для каждого запроса
- **🧪 Тестируемость** — Протоколы для легкого мокирования и тестирования
- **📦 Zero Dependencies** — Никаких внешних зависимостей, только стандартная библиотека Swift
- **🛡️ Production Ready** — Протестировано, оптимизировано и готово к использованию

### 💎 Что делает EKNetwork особенным?

#### 🎨 Декларативный подход
Описывайте запросы как типы Swift — компилятор сам проверит правильность вашего кода:

```swift
struct SignInRequest: NetworkRequest {
    struct Response: Decodable {
        let token: String
        let user: User
    }
    // ...
}
```

#### 🔧 Композиция и переиспользование
Легко комбинируйте различные типы запросов, создавайте базовые классы для общих паттернов:

```swift
protocol AuthenticatedRequest: NetworkRequest {
    // Общая логика для авторизованных запросов
}
```

#### 🛡️ Предсказуемая обработка ошибок
Четкая иерархия ошибок с возможностью кастомной обработки:

```swift
do {
    let response = try await manager.send(request)
} catch let error as HTTPError {
    // Обработка HTTP ошибок
} catch NetworkError.unauthorized {
    // Обработка авторизации
}
```

#### ⚡ Минимальный boilerplate
Пишите меньше кода, делайте больше. Один запрос = одна структура:

```swift
struct GetUserRequest: NetworkRequest {
    typealias Response = User
    var path: String { "/users/\(id)" }
    var method: HTTPMethod { .get }
    let id: Int
}
```

#### 🧪 Полное тестовое покрытие
220 тестов покрывают все основные сценарии использования, включая edge cases. Покрытие кода **99%+** (минимум 99%, проверяется в CI).

---

## 📦 Установка

### Swift Package Manager

Добавьте EKNetwork в зависимости вашего проекта в `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/emvakar/EKNetwork.git", from: "1.6.1")
]
```

Или через Xcode:
1. File → Add Packages...
2. Введите URL репозитория: `https://github.com/emvakar/EKNetwork.git`
3. Выберите версию

Затем добавьте продукт в ваш target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "EKNetwork", package: "EKNetwork")
    ]
)
```

### Требования

- **Swift**: 6.0+
- **iOS**: 15.0+
- **macOS**: 15.0+

---

## 🚀 Быстрый старт

### 1. Создайте запрос

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

### 2. Отправьте запрос

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

**Вот и всё!** Всего несколько строк кода для полноценного сетевого запроса с типобезопасностью и обработкой ошибок.

---

## 📚 Документация

### 📖 Справочник API

Для полной документации API см. [API_RU.md](API_RU.md). Справочник включает:
- Полную документацию методов и свойств
- Описание параметров
- Примеры использования
- Детали обработки ошибок
- Соответствие протоколам

### Базовые примеры

#### Запросы с query параметрами

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

#### Загрузка файлов (Multipart)

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

#### Отслеживание прогресса загрузки

```swift
@MainActor
class UploadViewModel: ObservableObject {
    @Published var uploadProgress: Double = 0.0
    
    func uploadFile(_ data: Data) async throws {
        let progress = NetworkProgress()
        
        // Связываем прогресс с UI
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

#### Retry Policy для надежности

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
            // Повторяем только при сетевых ошибках
            if let urlError = error as? URLError {
                return urlError.code == .timedOut || 
                       urlError.code == .networkConnectionLost
            }
            return false
        }
    }
}
```

#### Автоматическое обновление токенов

```swift
class TokenManager: TokenRefreshProvider {
    func refreshTokenIfNeeded() async throws {
        // Ваша логика обновления токена
        let refreshRequest = RefreshTokenRequest(
            refreshToken: TokenStore.shared.refreshToken
        )
        let response = try await networkManager.send(refreshRequest, accessToken: nil)
        TokenStore.shared.accessToken = response.accessToken
    }
}

let manager = NetworkManager(baseURL: { baseURL })
manager.tokenRefresher = TokenManager()

// При получении 401 токен автоматически обновится и запрос повторится
let response = try await manager.send(
    ProtectedRequest(),
    accessToken: { TokenStore.shared.accessToken }
)
```

#### Кастомная обработка ошибок

```swift
struct APIRequest: NetworkRequest {
    typealias Response = APIResponse
    
    var path: String { "/api/data" }
    var method: HTTPMethod { .get }
    
    var errorDecoder: ((Data) -> Error?)? {
        { data in
            // Декодируем кастомную ошибку от сервера
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

### Расширенные возможности

#### Стриминговые ответы (NDJSON / SSE / chunked) — с 1.6.0 (Data-чанки с 1.7.0)

Получайте ответ по мере поступления данных, используя тот же `NetworkRequest`. Подходит для NDJSON-потоков, Server-Sent Events и chunked log/streaming endpoint'ов.

```swift
struct EventsStream: NetworkRequest {
    typealias Response = EmptyResponse   // при стриминге одиночный decode тела не используется
    var path: String { "/api/v1/events" }
    var method: HTTPMethod { .get }
}

let response = try await manager.stream(EventsStream(), accessToken: { token })

// По одному JSON-объекту на строку:
for try await event in response.ndjson(as: Event.self) {
    handle(event)
}
// …либо сырые UTF-8 строки / Data-чанки (границы чанков не семантичны):
// for try await line in response.lines() { … }
// for try await chunk in response.chunks { buffer.append(chunk) }
```

Заголовки, аутентификация, base URL и обновление токена на 401 работают так же, как в `send(_:)`. Полное описание — в [API_RU.md](API_RU.md#streaming-ndjson--sse).

#### Закодированные сегменты пути (`pathIsPercentEncoded`) — с 1.6.1

Когда endpoint ожидает **уже percent-encoded** сегмент пути (например `%2F` внутри GitLab `repository/files/:file_path`), задайте `pathIsPercentEncoded`, чтобы EKNetwork сохранил его дословно, а не закодировал `%` повторно в `%252F`.

```swift
struct ReadFile: NetworkRequest {
    typealias Response = FileBlob
    let projectID: Int
    let encodedFilePath: String          // напр. "src%2FApp%2Fmain.swift"

    var path: String { "/api/v4/projects/\(projectID)/repository/files/\(encodedFilePath)" }
    var pathIsPercentEncoded: Bool { true }
    var queryParameters: [String: String]? { ["ref": "main"] }
}
```

По умолчанию `false` — существующие запросы сохраняют обычное поведение `appendingPathComponent`.

#### Кастомные JSON кодеры/декодеры

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

#### Глобальный декодер ответов (опционально)

Если нужна единая стратегия декодирования для всех запросов (например, гибкие даты), можно передать глобальный декодер в `NetworkManager`.

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

По умолчанию глобальный декодер применяется только если запрос это разрешает.
Чтобы отключить для конкретного запроса (если используется кастомный `decodeResponse`), задайте:

```swift
var allowsResponseDecoderOverride: Bool { false }
```

Пример: гибкое декодирование даты (строка или unix seconds):

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

#### Динамический base URL

```swift
// Базовый URL вычисляется при каждом запросе через замыкание — без гонок
var currentBase = URL(string: "https://api.staging.example.com")!
let manager = NetworkManager(baseURL: { currentBase })

// Переключение на production: измените значение, захваченное замыканием
currentBase = URL(string: "https://api.example.com")!
// Все последующие запросы будут использовать новый URL

// Или читайте из конфига/окружения
let manager = NetworkManager(baseURL: { AppConfig.shared.apiBaseURL })
```

#### User-Agent конфигурация

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
// User-Agent будет автоматически добавлен ко всем запросам
```

---

## 🎓 Лучшие практики

### 1. Организация запросов

Группируйте запросы по функциональности для лучшей организации кода:

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

### 2. Централизованный NetworkManager

Создайте единую точку доступа к API:

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

// Использование
let profile = try await APIClient.shared.send(UserRequests.GetProfile())
```

### 3. Обработка ошибок

Используйте иерархию ошибок для правильной обработки:

```swift
func handleRequest<T: NetworkRequest>(_ request: T) async {
    do {
        let response = try await manager.send(request, accessToken: tokenProvider)
        // Обработка успешного ответа
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

### 4. Тестирование

Используйте протоколы для мокирования:

```swift
// Мок URLSession
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

// В тестах
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

## 🧪 Тестирование

EKNetwork имеет полное тестовое покрытие (220 тестов, 99%+) и предоставляет протоколы для легкого тестирования:

- ✅ Все HTTP методы (GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, TRACE, CONNECT)
- ✅ Query параметры
- ✅ Различные типы body (JSON, Form URL Encoded, Multipart, Raw Data)
- ✅ Retry policy
- ✅ Token refresh
- ✅ Error handling
- ✅ Progress tracking
- ✅ User-Agent configuration
- ✅ Content-Length headers

Запустите тесты:

```bash
swift test
```

---

## 🤝 Внесение вклада

Мы приветствуем вклад в проект! Пожалуйста, ознакомьтесь с [CONTRIBUTING.md](CONTRIBUTING.md) для получения подробной информации.

### Как помочь проекту

- ⭐ **Поставьте звезду** на GitHub — это помогает проекту быть более заметным
- 🐛 **Сообщайте об ошибках** — создавайте issues с подробным описанием проблемы
- 💡 **Предлагайте новые функции** — делитесь идеями по улучшению библиотеки
- 📝 **Улучшайте документацию** — помогайте делать документацию лучше
- 🔧 **Отправляйте Pull Requests** — исправления и новые функции всегда приветствуются
- 💬 **Расскажите о проекте** — поделитесь с друзьями и коллегами
- 🐦 **Следите за обновлениями** — watch репозиторий, чтобы быть в курсе

### Процесс внесения изменений

1. Fork репозитория
2. Создайте ветку для ваших изменений (`git checkout -b feature/amazing-feature`)
3. Внесите изменения и добавьте тесты
4. Убедитесь, что все тесты проходят (`swift test`)
5. Создайте Pull Request с подробным описанием изменений

Подробнее в [CONTRIBUTING.md](CONTRIBUTING.md).

---

## 💚 Поддержка проекта

EKNetwork — это open source проект, созданный с любовью для Swift сообщества. Если проект полезен для вас, рассмотрите возможность поддержки:

### Способы поддержки

- ⭐ **Поставьте звезду** на GitHub — это бесплатно и помогает проекту
- 🐛 **Сообщайте об ошибках** — помогайте улучшать качество
- 💡 **Предлагайте идеи** — делитесь своими мыслями о развитии
- 🔧 **Вносите код** — Pull Requests всегда приветствуются
- 📢 **Расскажите о проекте** — поделитесь в социальных сетях, блогах, на конференциях
- 💰 **Финансовая поддержка** — если хотите поддержать разработку финансово, свяжитесь с автором

### Почему важна поддержка?

- 🚀 Помогает проекту развиваться быстрее
- 🐛 Улучшает качество и стабильность
- 📚 Расширяет документацию и примеры
- 🌟 Делает проект более заметным в сообществе
- 💡 Вдохновляет на новые функции и улучшения

**Спасибо всем, кто поддерживает проект!** 🙏

---

## 📄 Лицензия

EKNetwork доступен под лицензией MIT. См. [LICENSE](LICENSE) для получения дополнительной информации.

---

## 🙏 Благодарности

Спасибо всем контрибьюторам, которые помогают улучшать EKNetwork!

Особую благодарность:
- Swift сообществу за вдохновение и feedback
- Всем, кто тестирует библиотеку и сообщает об ошибках
- Контрибьюторам, которые улучшают код и документацию

---

## 📞 Поддержка и контакты

- 💬 **Issues**: [GitHub Issues](https://github.com/emvakar/EKNetwork/issues)
- 📖 **API Reference**: [API_RU.md](API_RU.md) - Полная документация API
- 📚 **Документация**: [Full Documentation](https://github.com/emvakar/EKNetwork/wiki)
- 🔒 **Безопасность**: [SECURITY.md](SECURITY.md) для сообщений о уязвимостях

---

## 📊 Статус проекта

- ✅ **Stable**: Готов к использованию в production
- ✅ **Tested**: 21 тест покрывает основные сценарии
- ✅ **Documented**: Полная документация с примерами
- ✅ **Maintained**: Активная поддержка и развитие

## 📁 Структура проекта

Для разработчиков, желающих внести вклад в проект, см. [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) для понимания структуры проекта.

---

<div align="center">

**Сделано с ❤️ для Swift сообщества**

[⬆ Наверх](#-eknetwork)

[⭐ Поставьте звезду, если проект полезен для вас!](#)

</div>
