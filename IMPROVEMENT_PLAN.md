# План улучшений и рефакторинга EKNetwork

Документ актуален после внедрения улучшений из предыдущего анализа (baseURL closure, MultipartFormData safety, path normalization, NonRetriableError, Task cancellation, shared progress session, 155 тестов).

---

## 1. Оставшиеся риски и уязвимости

### 1.1 Force unwrap в ProgressSessionManager (низкий)

**Где:** `ProgressSessionManager.swift`, строка ~82: `URL(string: "about:blank")!`.

**Проблема:** Force unwrap при формировании fallback URL, если `task.originalRequest?.url` равен nil.

**Рекомендация:** Использовать `URL(string: "about:blank")` с `guard let` и запасным `Data()`/пустым ответом или объявить константу `private static let fallbackURL = URL(string: "about:blank")!` в одном месте.

### 1.2 ProgressSessionManager не использует внедрённую session

**Где:** При `request.progress != nil` всегда вызывается `ProgressSessionManager.execute()`, который использует статическую сессию и не подставляет `URLProtocol` из тестов.

**Проблема:** Progress-запросы нельзя замокать через `URLProtocol` в unit-тестах; покрытие ProgressSessionManager исключено из отчёта.

**Рекомендация:** Либо принимать опциональную сессию/протокол для progress (сложнее), либо оставить исключение из coverage и документировать. Альтернатива: интеграционные тесты с реальным сервером.

### 1.3 EKNetworkVersion fallbacks не покрыты

**Где:** `EKNetworkVersion.swift` — ветки env, Bundle, git tag.

**Проблема:** В тестах всегда срабатывает встроенная версия; остальные пути не выполняются.

**Рекомендация:** Оставить в исключениях coverage или добавить тесты с подменой окружения (сложно без инъекции).

### 1.4 Логирование

**Где:** Path и ошибки логируются с `privacy: .private` — в продакшене детали не видны.

**Рекомендация:** Документировать в SECURITY.md/README: не помещать секреты в path и base URL; логи не содержат чувствительных данных при .private.

---

## 2. Рефакторинг

### 2.1 Разбиение NetworkManager.swift

**Цель:** Уменьшить размер файла, улучшить навигацию.

**План:**
- Вынести типы в отдельные файлы: `Errors.swift` (NetworkError, HTTPError, NonRetriableError), `MultipartFormData.swift`, `RequestBody.swift`, `RetryPolicy.swift`, `UserAgentConfiguration.swift`, протоколы в `Protocols.swift` или оставить в NetworkManager.
- В `NetworkManager.swift` оставить класс, `normalizePath`, `normalizeHeaders`, построение запроса.

**Приоритет:** Низкий.

### 2.2 Вынос построения URL и заголовков

**Цель:** Упростить тестирование и повторное использование.

**План:**
- Приватный метод `func buildURL(baseURL: URL, path: String, queryParameters: [String: String]?) throws -> URL`.
- Приватный метод `func applyHeaders(to request: inout URLRequest, request: NetworkRequest, ...)`.
- Вызовы из `performRequest`.

**Приоритет:** Средний.

### 2.3 Протокол NetworkManaging

**Цель:** Минимальный контракт для моков.

**План:** Не добавлять лишнего; при появлении новых публичных свойств менеджера дублировать в протоколе только то, что нужно тестам.

---

## 3. Улучшения API и совместимости

### 3.1 Документация emptyResponseHandler

**План:** В API.md и комментариях к `NetworkRequest` явно описать, когда использовать `emptyResponseHandler`, `EmptyResponse`, `StatusCodeResponse` (пустое тело при 2xx).

### 3.2 Версионирование и CHANGELOG

**План:** Перед каждым релизом обновлять CHANGELOG и тег; в IMPROVEMENT_PLAN.md указывать дату последнего обновления.

---

## 4. Приоритизация

| Приоритет | Элемент | Действие |
|-----------|--------|----------|
| Низкий | Force unwrap в ProgressSessionManager | Заменить на guard/константу |
| Низкий | Разбиение NetworkManager.swift | Вынести типы в отдельные файлы |
| Средний | Построение URL/заголовков | Вынести в приватные методы |
| Низкий | Документация emptyResponseHandler | Обновить API.md и комментарии |
| Инфо | ProgressSessionManager coverage | Оставить в исключениях или добавить интеграционные тесты |
| Инфо | EKNetworkVersion fallbacks | Оставить в исключениях coverage |

---

## 5. Чек-лист перед релизом

- [ ] Все тесты проходят (`swift test`)
- [ ] Coverage не ниже порога (`./scripts/coverage.sh`)
- [ ] CHANGELOG обновлён
- [ ] Версия в Package.swift и Version.swift согласованы
- [ ] Нет force unwrap в новых путях (кроме обоснованных)
- [ ] SECURITY.md актуален при изменении обработки данных
