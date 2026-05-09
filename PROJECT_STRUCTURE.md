# EKNetwork Project Structure

This document describes the structure of the EKNetwork project.

## 📁 Directory Structure

```
EKNetwork/
├── .github/                    # GitHub configuration
│   ├── ISSUE_TEMPLATE/         # Issue templates
│   │   ├── bug_report.md       # Bug report template
│   │   └── feature_request.md  # Feature request template
│   ├── workflows/              # GitHub Actions workflows
│   │   └── swift.yml          # CI/CD for Swift
│   ├── CODEOWNERS             # Code owners
│   ├── FUNDING.yml            # Funding information
│   └── pull_request_template.md # Pull Request template
│
├── Sources/                    # Library source code
│   └── EKNetwork/
│       ├── NetworkManager.swift # Main library code (request pipeline, retry, token refresh)
│       ├── Streaming.swift      # Streaming responses: NDJSON / SSE / chunked transfer (since 1.6.0)
│       ├── ProgressSessionManager.swift # Shared session for upload/download progress
│       ├── EKNetworkVersion.swift # Runtime version resolution helper
│       └── Version.swift       # Library version (auto-updated from git tag)
│
├── Tests/                      # Tests
│   └── EKNetworkTests/
│       ├── NetworkManagerTests.swift # Unit tests for NetworkManager / send pipeline
│       ├── StreamingTests.swift      # Unit tests for stream(_:) pipeline
│       ├── HighCoverageTests.swift   # Edge-case coverage
│       ├── CoverageImprovementsTests.swift # Additional coverage
│       ├── ExtendedTestSuite.swift   # Extended scenarios
│       ├── ExtendedCoverageTests.swift # Extended coverage
│       └── AdditionalCoverageTests.swift # Misc coverage
│
├── scripts/                    # Development scripts
│   ├── release.sh             # Release script
│   └── README.md              # Scripts documentation
│
├── .gitignore                  # Git ignore rules
├── CHANGELOG.md               # Change history
├── CODE_OF_CONDUCT.md         # Code of conduct
├── CONTRIBUTING.md            # Contribution guide
├── LICENSE                    # MIT license
├── Makefile                   # Make commands
├── Package.swift              # Swift Package Manager configuration
├── PROJECT_STRUCTURE.md       # This file
├── README.md                  # Main documentation
├── SECURITY.md                # Security policy
└── SUPPORT.md                 # Support information
```

## 📄 File Descriptions

### Documentation

- **README.md** - Main project documentation with usage examples
- **CHANGELOG.md** - History of all project changes
- **CONTRIBUTING.md** - Guide for those who want to contribute
- **CODE_OF_CONDUCT.md** - Code of conduct for the community
- **SECURITY.md** - Security policy and vulnerability reporting process
- **SUPPORT.md** - Information on how to get support
- **PROJECT_STRUCTURE.md** - This file describing the project structure

### Configuration

- **Package.swift** - Swift Package Manager configuration
- **.gitignore** - Git rules for which files to ignore
- **Makefile** - Commands for automating development tasks
- **LICENSE** - MIT license for the project

### GitHub Configuration

- **.github/ISSUE_TEMPLATE/** - Templates for creating Issues
- **.github/workflows/** - GitHub Actions for CI/CD
- **.github/CODEOWNERS** - Defines code owners for automatic review
- **.github/FUNDING.yml** - Information about funding methods
- **.github/pull_request_template.md** - Pull Request template

### Source Code

- **Sources/EKNetwork/** - Main library code
  - `NetworkManager.swift` - Main class for network operations (request building, retry policy, token refresh, JSON decoding)
  - `Streaming.swift` - Streaming response API: `URLSessionStreamingProtocol`, `NetworkStreaming`, `StreamingResponse`, `StreamingError`, `NetworkManager.stream(_:accessToken:)` (since 1.6.0)
  - `ProgressSessionManager.swift` - Shared `URLSession` for upload/download progress requests
  - `EKNetworkVersion.swift` - Runtime version resolution (embedded → env var → bundle → git tag)
  - `Version.swift` - Embedded library version string (auto-updated from git tag during release)

### Tests

- **Tests/EKNetworkTests/** - Unit tests for the library
  - `NetworkManagerTests.swift` - Tests for NetworkManager / `send(_:)` pipeline
  - `StreamingTests.swift` - Tests for `stream(_:accessToken:)` pipeline (NDJSON, CRLF, 401 refresh, error decoding)
  - Coverage suites: `HighCoverageTests`, `CoverageImprovementsTests`, `ExtendedTestSuite`, `ExtendedCoverageTests`, `AdditionalCoverageTests`

### Scripts

- **scripts/** - Helper scripts for development
  - `release.sh` - Script for creating releases

## 🚀 Quick Start for Developers

1. Clone the repository:
   ```bash
   git clone https://github.com/emvakar/EKNetwork.git
   cd EKNetwork
   ```

2. Open the project in Xcode or use Swift Package Manager:
   ```bash
   swift build
   swift test
   ```

3. Read [CONTRIBUTING.md](CONTRIBUTING.md) to understand the development process

4. Create a branch for your changes:
   ```bash
   git checkout -b feature/your-feature
   ```

5. Make changes and run tests:
   ```bash
   swift test
   ```

6. Create a Pull Request

## 📝 Code Standards

- Follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- Use `async/await` for asynchronous operations
- Add documentation for public APIs
- Write tests for new functionality
- Update CHANGELOG.md when adding new features

## 🔍 Where to Find Things

- **Usage examples** → README.md
- **How to contribute** → CONTRIBUTING.md
- **Report a bug** → .github/ISSUE_TEMPLATE/bug_report.md
- **Suggest a feature** → .github/ISSUE_TEMPLATE/feature_request.md
- **Security issues** → SECURITY.md
- **Get support** → SUPPORT.md
- **Change history** → CHANGELOG.md

---

## 🇷🇺 Русский

### Структура проекта

Проект EKNetwork организован следующим образом:

- `Sources/EKNetwork/` - исходный код библиотеки
- `Tests/EKNetworkTests/` - тесты
- `.github/` - конфигурация GitHub
- Документация в корне проекта

Подробнее см. английскую версию выше.
