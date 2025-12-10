# Справочник API EKNetwork

Полная документация API библиотеки EKNetwork.

## Содержание

- [NetworkManager](#networkmanager)
- [NetworkRequest](#networkrequest)
- [HTTPMethod](#httpmethod)
- [RequestBody](#requestbody)
- [MultipartFormData](#multipartformdata)
- [RetryPolicy](#retrypolicy)
- [NetworkProgress](#networkprogress)
- [TokenRefreshProvider](#tokenrefreshprovider)
- [Типы ошибок](#типы-ошибок)
- [Типы ответов](#типы-ответов)
- [UserAgentConfiguration](#useragentconfiguration)

---

## NetworkManager

Основной класс для управления сетевыми запросами.

### Инициализация

```swift
public init(
    baseURL: URL,
    session: URLSessionProtocol = URLSession.shared,
    loggerSubsystem: String = "com.yourapp.networking",
    userAgentConfiguration: UserAgentConfiguration? = nil
)
```

**Параметры:**
- `baseURL`: Базовый URL, к которому будут добавляться пути запросов
- `session`: `URLSessionProtocol` для выполнения запросов (по умолчанию `URLSession.shared`)
- `loggerSubsystem`: Идентификатор подсистемы для экземпляра `Logger`
- `userAgentConfiguration`: Опциональная конфигурация User-Agent

### Свойства

#### `baseURL: URL`
Базовый URL, к которому будут добавляться пути запросов. Может быть изменен динамически с помощью метода `updateBaseURL(_:)`.

#### `tokenRefresher: TokenRefreshProvider?`
Опциональный обновлятель токенов для обработки обновления токенов аутентификации. При установке автоматически обновляет токены при ответах 401.

#### `userAgentConfiguration: UserAgentConfiguration?`
Конфигурация User-Agent. При установке автоматически добавляет заголовок User-Agent ко всем запросам.

### Методы

#### `send<T: NetworkRequest>(_ request: T, accessToken: (() -> String?)?) async throws -> T.Response`

Отправляет сетевой запрос и декодирует ответ.

**Параметры:**
- `request`: Сетевой запрос для отправки
- `accessToken`: Опциональное замыкание, возвращающее токен доступа для аутентификации

**Возвращает:** Декодированный ответ типа `T.Response`

**Выбрасывает:** Ошибки, возникшие во время запроса или декодирования

**Пример:**
```swift
let response = try await manager.send(
    SignInRequest(email: "user@example.com", password: "password"),
    accessToken: { TokenStore.shared.accessToken }
)
```

#### `updateBaseURL(_ newBaseURL: URL)`

Обновляет базовый URL для всех последующих сетевых запросов.

**Параметры:**
- `newBaseURL`: Новый базовый URL для использования

**Примечание:** Это изменение вступает в силу немедленно для всех новых запросов. Запросы, которые в настоящее время выполняются, будут по-прежнему использовать старый базовый URL.

---

## NetworkRequest

Протокол, представляющий сетевой запрос. Соответствующие типы определяют путь запроса, метод, заголовки, параметры и тип ответа.

### Обязательные свойства

#### `associatedtype Response: Decodable`
Ожидаемый тип ответа, должен соответствовать `Decodable`.

#### `var path: String { get }`
Компонент пути, добавляемый к базовому URL.

#### `var method: HTTPMethod { get }`
HTTP метод для запроса.

### Опциональные свойства (с значениями по умолчанию)

#### `var headers: [String: String]? { get }`
Опциональные HTTP заголовки для включения в запрос. По умолчанию `nil`.

#### `var queryParameters: [String: String]? { get }`
Опциональные параметры запроса, добавляемые к URL. По умолчанию `nil`.

#### `var contentType: String { get }`
Заголовок Content-Type для запроса. По умолчанию `"application/json"`.

#### `var body: RequestBody? { get }`
Опциональное тело, отправляемое с запросом, поддерживающее различные кодировки. По умолчанию `nil`.

#### `var multipartData: MultipartFormData? { get }`
Опциональные данные multipart формы для запросов на загрузку. По умолчанию `nil`.

#### `var progress: NetworkProgress? { get }`
Опциональный наблюдатель прогресса для загрузки/выгрузки. По умолчанию `nil`.

#### `var retryPolicy: RetryPolicy { get }`
Политика повторных попыток для применения к этому запросу. По умолчанию `RetryPolicy()`.

#### `var errorDecoder: ((Data) -> Error?)? { get }`
Опциональный декодер ошибок для извлечения ответов об ошибках с сервера. По умолчанию `nil`.

#### `var allowsRetry: Bool { get }`
Должен ли запрос разрешать повторные попытки и обновление токена при 401 Unauthorized? По умолчанию `true`.

#### `var emptyResponseHandler: ((HTTPURLResponse) throws -> Response)? { get }`
Опциональный обработчик, используемый, когда сервер возвращает пустое тело. По умолчанию `nil`.

#### `var jsonDecoder: JSONDecoder { get }`
Предоставляет экземпляр декодера для JSON ответов. По умолчанию `JSONDecoder()`.

#### `var jsonEncoder: JSONEncoder { get }`
Предоставляет экземпляр кодировщика для JSON тел запросов. По умолчанию `JSONEncoder()`.

### Методы

#### `func decodeResponse(data: Data, response: URLResponse) throws -> Response`

Декодирует сырой ответ в связанный тип ответа.

**Параметры:**
- `data`: Данные ответа
- `response`: URL ответ

**Возвращает:** Декодированный ответ типа `Response`

**Выбрасывает:** Ошибки декодирования

**Реализация по умолчанию:** Обрабатывает JSON декодирование и резервные варианты для пустых ответов.

---

## HTTPMethod

Перечисление, представляющее HTTP методы, поддерживаемые сетевой прослойкой.

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

Представляет тело запроса для сетевого запроса, поддерживающее различные типы.

### Инициализаторы

#### `init(encodable: Encodable, contentType: String = "application/json")`

Создает тело запроса из кодируемого объекта (обычно для JSON).

**Параметры:**
- `encodable`: Кодируемый объект для кодирования
- `contentType`: Тип контента (по умолчанию `"application/json"`)

#### `init(data: Data, contentType: String)`

Создает тело запроса из сырых данных.

**Параметры:**
- `data`: Сырые данные
- `contentType`: Тип контента

#### `init(stream: InputStream, contentType: String)`

Создает тело запроса из потока ввода (для больших загрузок).

**Параметры:**
- `stream`: Поток ввода
- `contentType`: Тип контента

#### `init(formURLEncoded parameters: [String: String])`

Создает тело запроса с кодированием формы URL.

**Параметры:**
- `parameters`: Пары ключ-значение для данных формы URL

**Тип контента:** Автоматически устанавливается в `"application/x-www-form-urlencoded"`

### Типы контента

`RequestBody` поддерживает следующие типы контента:

- `.encodable(Encodable)` - JSON-кодируемый объект
- `.raw(Data)` - Сырые двоичные или предварительно закодированные данные
- `.stream(InputStream)` - Поток для больших загрузок данных
- `.formURLEncoded([String: String])` - Пары ключ-значение для данных формы URL

---

## MultipartFormData

Представляет данные multipart формы для загрузки файлов.

### Свойства

#### `boundary: String`
Уникальная строка границы, используемая для разделения частей. Автоматически генерируется как UUID.

#### `parts: [Part]`
Массив частей, включенных в multipart форму.

### Методы

#### `mutating func addPart(name: String, data: Data, mimeType: String, filename: String? = nil)`

Добавляет новую часть к данным multipart формы.

**Параметры:**
- `name`: Имя поля формы
- `data`: Содержимое данных
- `mimeType`: Строка MIME типа
- `filename`: Опциональное имя файла

#### `func encodedData() -> Data`

Кодирует данные multipart формы в объект Data, подходящий для HTTP тела.

**Возвращает:** Закодированные данные, представляющие multipart форму

### Структура Part

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

Определяет поведение повторных попыток для сетевых запросов.

### Свойства

#### `maxRetryCount: Int`
Максимальное количество попыток повторной попытки.

#### `delay: TimeInterval`
Задержка в секундах перед повторной попыткой запроса.

#### `shouldRetry: (Error) -> Bool`
Замыкание для определения, должна ли быть повторная попытка на основе возникшей ошибки.

### Инициализация

```swift
public init(
    maxRetryCount: Int = 0,
    delay: TimeInterval = 1.0,
    shouldRetry: @escaping (Error) -> Bool = { /* реализация по умолчанию */ }
)
```

**Поведение по умолчанию:**
- Не повторяет при `NetworkError.unauthorized`
- Не повторяет при `URLError.userAuthenticationRequired`
- Не повторяет при пользовательских ошибках API (типы, содержащие "APIError", "ServerError" или "Business")
- Повторяет при других ошибках

---

## NetworkProgress

Наблюдаемый объект для отслеживания прогресса загрузки или выгрузки сети.

### Свойства

#### `@Published var fractionCompleted: Double`
Доля выполненной задачи, от 0.0 до 1.0.

### Использование

```swift
@MainActor
class UploadViewModel: ObservableObject {
    @Published var uploadProgress: Double = 0.0
    
    func uploadFile(_ data: Data) async throws {
        let progress = NetworkProgress()
        progress.$fractionCompleted
            .assign(to: &$uploadProgress)
        
        // Используйте progress в запросе
        struct UploadRequest: NetworkRequest {
            var progress: NetworkProgress? { progress }
            // ...
        }
    }
}
```

---

## TokenRefreshProvider

Протокол для предоставления функциональности обновления токенов.

### Методы

#### `func refreshTokenIfNeeded() async throws`

Обновляет токен аутентификации при необходимости. Этот метод вызывается автоматически при получении ответа 401 Unauthorized.

**Пример:**
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

## Типы ошибок

### NetworkError

Ошибки, которые могут возникнуть во время сетевых операций.

```swift
public enum NetworkError: Error {
    case invalidURL          // URL не может быть построен
    case emptyResponse       // Данные ответа были пустыми
    case unauthorized        // Неавторизованный доступ, обычно HTTP 401
    case invalidResponse     // Ответ отсутствовал или имел неожиданный тип
    case conflictingBodyTypes // И body, и multipartData установлены
}
```

### HTTPError

Общая HTTP ошибка, несущая код состояния и полезную нагрузку для диагностики.

```swift
public struct HTTPError: LocalizedError {
    public let statusCode: Int
    public let data: Data
    public let headers: [String: String]
    
    public var errorDescription: String? {
        "Запрос завершился с кодом состояния \(statusCode)"
    }
}
```

---

## Типы ответов

### StatusCodeResponse

Удобный ответ, который только раскрывает HTTP код состояния и заголовки.

```swift
public struct StatusCodeResponse: Decodable, Equatable {
    public let statusCode: Int
    public let headers: [String: String]
}
```

### EmptyResponse

Представляет пустую полезную нагрузку. Полезно для конечных точек, которые только сигнализируют об успехе через код состояния.

```swift
public struct EmptyResponse: Decodable, Equatable {
    public init() {}
}
```

---

## UserAgentConfiguration

Конфигурация для генерации заголовка User-Agent.

### Свойства

- `appName: String` - Имя приложения
- `appVersion: String` - Версия приложения
- `bundleIdentifier: String` - Идентификатор пакета
- `buildNumber: String` - Номер сборки
- `osVersion: String` - Версия iOS/OS
- `networkVersion: String` - Версия фреймворка EKNetwork

### Инициализация

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

Все параметры опциональны и по умолчанию берутся из `Bundle.main` или системных значений по умолчанию.

### Методы

#### `func generateUserAgentString() -> String`

Генерирует строку User-Agent в формате:
`AppName/Version (BundleID; build:BuildNumber; Platform OSVersion) EKNetwork/Version`

---

## Абстракции протоколов

### NetworkManaging

Абстракция протокола для NetworkManager, позволяющая мокирование и внедрение зависимостей.

```swift
public protocol NetworkManaging {
    var tokenRefresher: TokenRefreshProvider? { get set }
    func send<T: NetworkRequest>(_ request: T, accessToken: (() -> String?)?) async throws -> T.Response
}
```

### URLSessionProtocol

Абстракция протокола для URLSession, позволяющая мокирование и внедрение зависимостей.

```swift
public protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
```

`URLSession` по умолчанию соответствует этому протоколу.

---

[English version](API.md)

