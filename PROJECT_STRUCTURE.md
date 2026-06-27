# EKNetwork Project Structure

This document describes the structure of the EKNetwork project.

## 📁 Directory Structure

```
EKNetwork/
├── .github/                    # GitHub configuration
│   ├── ISSUE_TEMPLATE/         # Issue templates
│   │   ├── bug_report.md       # Bug report template
│   │   ├── feature_request.md  # Feature request template
│   │   └── improvement.md      # Improvement template
│   ├── workflows/              # GitHub Actions workflows
│   │   ├── swift.yml          # CI: build, test, coverage gate (push / PR)
│   │   └── release.yml       # Release: build + formatted GitHub Release on version tag
│   ├── CODEOWNERS             # Code owners
│   ├── FUNDING.yml            # Funding information
│   ├── RELEASE_TEMPLATE.md    # Release notes template
│   └── pull_request_template.md # Pull Request template
│
├── docs/                       # Topic guides
│   └── Releasing.md           # Release & versioning process (tag → GitHub Release)
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
│   ├── release.sh             # Manual version bump + tag helper
│   ├── release_notes.sh       # Build formatted release notes (CHANGELOG / commit fallback)
│   ├── coverage.sh            # Generate coverage report and enforce the 98% gate
│   ├── create_issues.sh       # Automated GitHub issue creation
│   ├── README.md              # Scripts documentation
│   └── README_ISSUES.md       # Issue-automation documentation
│
├── .gitignore                  # Git ignore rules
├── API.md / API_RU.md         # Full API reference (EN / RU)
├── CHANGELOG.md               # Change history (emoji sections, 1.0.0 → latest)
├── CODE_OF_CONDUCT.md         # Code of conduct
├── CONTRIBUTING.md            # Contribution guide
├── LICENSE                    # MIT license
├── Makefile                   # Make commands
├── Package.swift              # Swift Package Manager configuration
├── PROJECT_STRUCTURE.md       # This file
├── README.md / README_RU.md   # Main documentation (EN / RU)
├── ROADMAP.md                 # Planned improvements and known issues
├── SECURITY.md                # Security policy
├── SUMMARY.md                 # Executive summary for evaluators
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
- **.github/workflows/swift.yml** - CI on push / PR: build, tests, 98% coverage gate
- **.github/workflows/release.yml** - Builds and publishes a formatted GitHub Release on a version tag
- **.github/CODEOWNERS** - Defines code owners for automatic review
- **.github/FUNDING.yml** - Information about funding methods
- **.github/RELEASE_TEMPLATE.md** - Release notes template
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

### Topic Guides

- **docs/Releasing.md** - End-to-end release & versioning process: tagging, the `release.yml` workflow, CHANGELOG format and the notes generator

### Scripts

- **scripts/** - Helper scripts for development
  - `release.sh` - Manual version bump + tag helper
  - `release_notes.sh` - Builds formatted release notes (CHANGELOG section, or emoji-categorized commit fallback)
  - `coverage.sh` - Generates the coverage report and enforces the 98% gate
  - `create_issues.sh` - Automated GitHub issue creation

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
- **Full API reference** → API.md (EN) / API_RU.md (RU)
- **How to release** → docs/Releasing.md
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
