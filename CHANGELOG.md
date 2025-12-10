# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.2] - 2025-12-09

### Added
- Added validation for conflict between `body` and `multipartData`
- Added new error type `NetworkError.conflictingBodyTypes`
- Added `RequestBody(formURLEncoded:)` initializer for convenience
- Added `Content-Length` header for multipart data
- Race condition protection for `baseURL` (local copy at request start)

### Improved
- Improved code comments
- Added warnings about potential URLSession issues for progress tracking
- Used ephemeral configuration to reduce memory usage

### Fixed
- Fixed error handling for body type conflicts
- Improved documentation for retry logic after token refresh

## [1.2.1] - 2025-XX-XX

### Added
- Swift 6.0 support
- Improved error handling

## [1.2.0] - 2025-XX-XX

### Added
- Progress tracking support for uploads and downloads
- User-Agent configuration
- Dynamic base URL changes
- Extended retry policy system

## [1.1.0] - 2025-XX-XX

### Added
- Multipart form data support
- Form URL encoded support
- Raw data body support
- Stream body support
- Custom JSON encoder/decoder per request

## [1.0.0] - 2025-XX-XX

### Added
- Initial release
- Basic NetworkManager functionality
- Async/await support
- Type-safe API via NetworkRequest protocol
- Automatic token refresh
- Retry policy
- Error handling

---

## Types of Changes

- `Added` - for new features
- `Changed` - for changes in existing functionality
- `Deprecated` - for soon-to-be removed features
- `Removed` - for removed features
- `Fixed` - for any bug fixes
- `Security` - in case of vulnerabilities

---

## 🇷🇺 Русский

### [1.2.2] - 2025-12-09

#### Добавлено
- Добавлена валидация конфликта между `body` и `multipartData`
- Добавлен новый тип ошибки `NetworkError.conflictingBodyTypes`
- Добавлен инициализатор `RequestBody(formURLEncoded:)` для удобства
- Добавлен заголовок `Content-Length` для multipart данных
- Защита от race condition с `baseURL`

#### Улучшено
- Улучшены комментарии в коде
- Добавлены предупреждения о потенциальных проблемах с URLSession

#### Исправлено
- Исправлена обработка ошибок при конфликте типов body
- Улучшена документация по логике retry после token refresh
