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
- [Стриминг (NDJSON / SSE)](#стриминг-ndjson--sse)
- [Типы ошибок](#типы-ошибок)
- [Типы ответов](#типы-ответов)
- [UserAgentConfiguration](#useragentconfiguration)

---

## NetworkManager

Основной класс для управления сетевыми запросами.

### Инициализация

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

**Параметры:**
- `baseURL`: Замыкание, возвращающее базовый URL для каждого запроса. Используйте `{ myURL }` для фиксированного URL или замыкание, читающее из конфига/окружения, для динамического базового URL (без гонок при переключении окружений).
- `session`: `URLSessionProtocol` для выполнения запросов (по умолчанию `URLSession.shared`)
- `streamingSession`: Опциональная сессия для `stream(_:accessToken:)` (NDJSON / SSE / chunked transfer). Если не передана, менеджер использует `session`, если та поддерживает `URLSessionStreamingProtocol` (`URLSession` поддерживает по умолчанию), иначе — `URLSession.shared`. Добавлено в 1.6.0; существующие вызовы инициализатора остаются совместимыми.
- `loggerSubsystem`: Идентификатор подсистемы для экземпляра `Logger`
- `userAgentConfiguration`: Опциональная конфигурация User-Agent
- `responseDecoderProvider`: Опциональный глобальный JSON-декодер для ответов (может переопределять декодирование запросов)

**Пример:**
```swift
// Фиксированный базовый URL
let manager = NetworkManager(baseURL: { URL(string: "https://api.example.com")! })

// Динамический базовый URL (например, из настроек)
let manager = NetworkManager(baseURL: { AppSettings.shared.apiBaseURL })
```

### Свойства

#### `baseURL: () -> URL`
Замыкание, возвращающее базовый URL; вызовите `baseURL()` для получения текущего базового URL. Каждый запрос вызывает это замыкание, поэтому URL может меняться между запросами без гонок.

#### `tokenRefresher: TokenRefreshProvider?`
Опциональный обновлятель токенов для обработки обновления токенов аутентификации. При установке автоматически обновляет токены при ответах 401.

#### `userAgentConfiguration: UserAgentConfiguration?`
Конфигурация User-Agent. При установке автоматически добавляет заголовок User-Agent ко всем запросам.

#### `responseDecoderProvider: (() -> JSONDecoder)?`
Опциональный глобальный декодер JSON-ответов. Если задан, может переопределять декодирование на уровне запросов.

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

---

## NetworkRequest

Протокол, представляющий сетевой запрос. Соответствующие типы определяют путь запроса, метод, заголовки, параметры и тип ответа.

### Обязательные свойства

#### `associatedtype Response: Decodable`
Ожидаемый тип ответа, должен соответствовать `Decodable`.

#### `var path: String { get }`
Компонент пути, добавляемый к базовому URL. По умолчанию путь считается **не** percent-encoded: он нормализуется (срезаются ведущие/замыкающие слэши, схлопываются `//`, отклоняются `..`) и присоединяется к базовому URL через `appendingPathComponent`. Чтобы встроить уже закодированные зарезервированные символы (например `%2F` в GitLab `repository/files/:file_path`), задайте `pathIsPercentEncoded = true` — см. ниже.

#### `var method: HTTPMethod { get }`
HTTP метод для запроса.

### Опциональные свойства (с значениями по умолчанию)

#### `var pathIsPercentEncoded: Bool { get }`
Указывает, что `path` уже percent-encoded и должен использоваться как есть. По умолчанию `false`. Добавлено в **1.6.1**.

При `false` (по умолчанию) URL собирается через `appendingPathComponent`, который повторно кодирует `%` — сегмент `a%2Fb` превращается в `a%252Fb`. Это корректно для обычных путей, но ломает endpoint'ы, ожидающие заранее закодированный сегмент.

При `true` путь присоединяется через `percentEncodedPath`, сохраняя зарезервированные символы (`%2F` и т.п.) дословно. Используйте для API, принимающих закодированный идентификатор ресурса в пути:

```swift
struct ReadFileRequest: NetworkRequest {
    typealias Response = FileBlob
    let projectID: Int
    let encodedFilePath: String   // напр. "src%2FApp%2Fmain.swift"

    var path: String { "/api/v4/projects/\(projectID)/repository/files/\(encodedFilePath)" }
    var pathIsPercentEncoded: Bool { true }
    var queryParameters: [String: String]? { ["ref": "main"] }
}
```

Существующие запросы не затрагиваются: не задавайте свойство, чтобы сохранить прежнее поведение.

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

Когда сервер отвечает успешным кодом и нулевой длиной тела, `NetworkRequest` вызывает этот обработчик вместо JSON-декодирования. Если оставить `nil`, `decodeResponse` выбросит `NetworkError.emptyResponse`.

**Выбор подходящего подхода для пустых ответов:**

1. **Используйте `EmptyResponse`** (рекомендуется для простых случаев успеха):
   ```swift
   struct DeleteRequest: NetworkRequest {
       typealias Response = EmptyResponse
       // emptyResponseHandler предоставляется автоматически
   }
   ```
   Лучше всего для конечных точек, которые возвращают 204 No Content или пустые тела, когда вам нужно только подтвердить успех. Реализация по умолчанию игнорирует любые данные и возвращает `EmptyResponse()`.

2. **Используйте `StatusCodeResponse`** (когда нужны HTTP метаданные):
   ```swift
   struct UpdateRequest: NetworkRequest {
       typealias Response = StatusCodeResponse
       // emptyResponseHandler автоматически извлекает код состояния и заголовки
   }
   ```
   Лучше всего, когда вам нужно проверить HTTP код состояния или заголовки из ответа. Реализация по умолчанию копирует код состояния и заголовки из `HTTPURLResponse`.

3. **Предоставьте кастомный `emptyResponseHandler`** (для продвинутых случаев):
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
   Нужно только когда вы должны сформировать кастомный тип ответа из заголовков, кода состояния или других метаданных, сопровождающих пустой payload.

#### `var jsonDecoder: JSONDecoder { get }`
Предоставляет экземпляр декодера для JSON ответов. По умолчанию `JSONDecoder()`.

#### `var jsonEncoder: JSONEncoder { get }`
Предоставляет экземпляр кодировщика для JSON тел запросов. По умолчанию `JSONEncoder()`.

#### `var allowsResponseDecoderOverride: Bool { get }`
Разрешает ли `NetworkManager` переопределять декодирование этого запроса при наличии глобального декодера. По умолчанию `true`.

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
    case head = "HEAD"
    case options = "OPTIONS"
    case trace = "TRACE"
    case connect = "CONNECT"
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

## Стриминг (NDJSON / SSE)

> Доступно начиная с **1.6.0**.

`send(_:accessToken:)` рассчитан на эндпоинты, отдающие тело целиком одним `Decodable`-объектом. Для эндпоинтов, которые отдают данные постепенно — newline-delimited JSON, Server-Sent Events, chunked-логи / inference-стримы — используйте `stream(_:accessToken:)`. Стриминг переиспользует **тот же самый** пайплайн построения запроса (заголовки, `Authorization`, `User-Agent`, тело, baseURL), что и `send(_:)`. То есть прикладному коду никогда не нужно собирать `URLRequest` вручную и рисковать потерять обязательные заголовки вроде `X-Device-ID` или кастомной авторизации.

### Протокол NetworkStreaming

```swift
public protocol NetworkStreaming: AnyObject {
    func stream<T: NetworkRequest>(
        _ request: T,
        accessToken: (() -> String?)?
    ) async throws -> StreamingResponse
}
```

`NetworkManager` соответствует и `NetworkManaging`, и `NetworkStreaming`. Существующие моки `NetworkManaging` остаются рабочими.

### StreamingResponse

```swift
public struct StreamingResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let bytes: AsyncThrowingStream<UInt8, Error>

    public func lines() -> AsyncThrowingStream<String, Error>
    public func ndjson<Item: Decodable & Sendable>(
        as itemType: Item.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) -> AsyncThrowingStream<Item, Error>
}
```

- `bytes` — поток сырых байт (по одному `UInt8`), в порядке прихода.
- `lines()` — UTF-8 строки, разделённые `\n`, с обрезкой `\r` (CRLF-aware), пустые строки пропускаются. Корректно собирает многобайтовые UTF-8 последовательности, разрезанные TCP-сегментами.
- `ndjson(as:decoder:)` — по одному `Decodable`-объекту на каждую непустую строку. Битая строка — стрим завершается ошибкой.

Отмена пробрасывается автоматически: выход из `for try await` или отмена внешнего `Task` отменяет сетевую задачу.

### URLSessionStreamingProtocol

```swift
public protocol URLSessionStreamingProtocol: Sendable {
    func byteStream(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse)
}
```

`URLSession` соответствует протоколу по умолчанию (мостит `URLSession.bytes(for:)` в полностью `Sendable`-стрим). Реализуйте этот протокол в моках, если хотите тестировать стриминговый пайплайн без сети.

### Поведение в сравнении с `send(_:)`

| Аспект | `send(_:)` | `stream(_:)` |
|---|---|---|
| Заголовки, тело, авторизация | `buildURLRequest` | `buildURLRequest` (та же точка) |
| 401 → refresh + retry | один раз, если `allowsRetry == true` | один раз, до того как пришёл хоть один байт тела |
| 401 в середине стрима | n/a | не ретраится (тело уже начали отдавать) |
| Не-2xx ошибка | `HTTPError` / `errorDecoder` | drain ≤1 МиБ, затем `HTTPError` / `errorDecoder` |
| RetryPolicy | применяется | не применяется (стрим нельзя детерминированно проиграть заново) |
| NetworkProgress | применяется | не применяется |

### StreamingError

```swift
public enum StreamingError: Error, Equatable {
    case invalidResponse                          // ответ не HTTPURLResponse
    case errorPayloadTooLarge(limitBytes: Int)    // тело не-2xx ответа превысило 1 МиБ
}
```

### Пример: NDJSON-поиск

```swift
struct PlayerSearchRequest: NetworkRequest {
    typealias Response = EmptyResponse  // не используется в стриминге
    var path: String { "/api/v1/players/search" }
    var method: HTTPMethod { .get }
    var queryParameters: [String: String]? { ["q": query, "stream": "true"] }
    var headers: [String: String]? { DeviceHeaders.current() }
    let query: String
}

let response = try await manager.stream(
    PlayerSearchRequest(query: "Бобр"),
    accessToken: { TokenStore.shared.accessToken }
)

for try await item in response.ndjson(as: SearchEvent.self) {
    handle(item)            // отрисовка по мере поступления
    if case .end = item { break }
}
```

### Пример: Server-Sent Events

```swift
let response = try await manager.stream(MyEventsRequest(), accessToken: nil)
for try await line in response.lines() {
    guard line.hasPrefix("data:") else { continue }
    let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
    process(payload)
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

Используйте этот тип, когда вам важны только код состояния и заголовки, а тело можно игнорировать. Стандартный `emptyResponseHandler` для `Response == StatusCodeResponse` копирует код и заголовки из пустого `HTTPURLResponse`, поэтому вы получаете эти значения без декодирования тела.

### EmptyResponse

Представляет пустую полезную нагрузку. Полезно для конечных точек, которые только сигнализируют об успехе через код состояния.

```swift
public struct EmptyResponse: Decodable, Equatable {
    public init() {}
}
```

`EmptyResponse` годится для сценариев, где сервер возвращает 204/пустое тело и вам нужно только подтвердить успех. Реализация `decodeResponse` по умолчанию сразу возвращает `EmptyResponse()` и игнорирует payload, так что вы можете рассматривать этот тип как маркер void-успеха.

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
