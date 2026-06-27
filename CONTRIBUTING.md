# Contributing to EKNetwork

Thank you for your interest in contributing to EKNetwork! We're happy to have you. This document contains guidelines for the contribution process.

## How to Contribute

### Reporting Bugs

If you found a bug:

1. Check if it has already been reported in [Issues](https://github.com/emvakar/EKNetwork/issues)
2. If not reported, create a new issue with:
   - Clear description of the problem
   - Steps to reproduce
   - Expected and actual behavior
   - Swift and platform version
   - Minimal code example demonstrating the problem

### Suggesting Enhancements

We welcome enhancement suggestions! Create an issue with:
- Description of the proposed enhancement
- Justification of why this enhancement is useful
- Usage example, if applicable

### Pull Requests

1. **Fork the repository** and create a branch for your changes:
   ```bash
   git checkout -b feature/amazing-feature
   ```

2. **Follow code style**:
   - Use SwiftLint (if configured)
   - Follow existing formatting style
   - Add comments for complex logic

3. **Add tests**:
   - New features should include tests
   - Ensure all tests pass: `swift test`
   - Aim for code coverage

4. **Update documentation**:
   - Update README.md if adding new features
   - Add usage examples
   - Update code comments

5. **Ensure code compiles**:
   ```bash
   swift build
   swift test
   ```

6. **Create Pull Request**:
   - Describe changes in PR
   - Reference related issues
   - Ensure CI passes

## Development Process

### Environment Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/emvakar/EKNetwork.git
   cd EKNetwork
   ```

2. Ensure you have Swift 6.0 or newer installed

3. Run tests:
   ```bash
   swift test
   ```

### Project Structure

- `Sources/EKNetwork/` - library source code
- `Tests/EKNetworkTests/` - tests
- `README.md` - documentation
- `Package.swift` - Swift Package Manager configuration

### Code Standards

- Use `async/await` for asynchronous operations
- Follow Swift API Design Guidelines principles
- Use `@MainActor` where necessary for thread-safety
- Add documentation for public APIs

### Testing

- Write unit tests for new functionality
- Use `@testable import EKNetwork` for testing internal components
- Aim for coverage of all edge cases — CI enforces a **98% minimum** (`scripts/coverage.sh`)

### Releasing

Releases are automated from version tags. Before tagging, bump
`Sources/EKNetwork/Version.swift` and add a `CHANGELOG.md` section. The full
process — tagging, the `release.yml` workflow and the notes generator — is
described in [docs/Releasing.md](docs/Releasing.md).

## Questions?

If you have questions, create an issue or contact the project maintainers.

Thank you for your contribution! 🎉

---

## 🇷🇺 Русский

### Как внести вклад

#### Сообщение об ошибках

Если вы нашли ошибку:

1. Проверьте, не была ли она уже зарегистрирована в [Issues](https://github.com/emvakar/EKNetwork/issues)
2. Если ошибка не зарегистрирована, создайте новую issue с подробным описанием

#### Pull Requests

1. Fork репозитория и создайте ветку
2. Следуйте стилю кода
3. Добавьте тесты
4. Обновите документацию
5. Создайте Pull Request

Подробнее см. английскую версию выше.
