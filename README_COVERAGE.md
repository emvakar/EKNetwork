# Code Coverage Guide

This guide explains how to check code coverage locally and understand the coverage reports.

## Quick Start

### Check Coverage Locally

Simply run the coverage script:

```bash
./scripts/coverage.sh
```

This will:
1. Run tests with code coverage enabled
2. Generate a coverage report
3. Calculate coverage percentage
4. Display the results
5. Check if coverage meets the 98% requirement

### Manual Steps

If you prefer to run steps manually:

```bash
# 1. Run tests with coverage
swift test --enable-code-coverage

# 2. Find the coverage data file
PROFDATA=$(find .build -name "*.profdata" | head -1)

# 3. Find the test binary
TEST_BINARY=$(find .build -path "*/EKNetworkPackageTests.xctest/Contents/MacOS/EKNetworkPackageTests" | head -1)

# 4. Generate coverage report
xcrun llvm-cov show \
  -instr-profile "$PROFDATA" \
  "$TEST_BINARY" \
  -arch arm64 \
  -format=text \
  -ignore-filename-regex=".*Tests.*|.*Version\.swift" \
  > coverage_report.txt

# 5. View the report
cat coverage_report.txt
```

## Understanding Coverage Reports

### Coverage Report Format

The coverage report shows each line of code with its execution count:

```
    line_number|execution_count|code
```

Example:
```
    21|      1|        let embeddedVersion = EKNetworkVersionString
    30|      0|        // Priority 2: Environment variable
```

- **Line number**: The line number in the source file
- **Execution count**: How many times this line was executed during tests
  - `0` = not covered (line was never executed)
  - `1+` = covered (line was executed at least once)
- **Code**: The actual source code

### Coverage Calculation

- **Total lines**: All executable lines in the source code
- **Covered lines**: Lines that were executed at least once during tests
- **Coverage percentage**: `(Covered lines / Total lines) * 100`

### Current Coverage

The project aims for **98% code coverage**. Currently, coverage is calculated excluding:
- Test files (`*Tests.swift`)
- Auto-generated files (`Version.swift`)

## Viewing Detailed Coverage

### View Coverage for Specific File

```bash
# Generate full report
./scripts/coverage.sh

# View coverage for NetworkManager.swift
grep -A 50 "NetworkManager.swift" coverage_report.txt
```

### Find Uncovered Lines

```bash
# Find lines with 0 execution count
grep -E "^[[:space:]]*[0-9]+\|[[:space:]]*0\|" coverage_report.txt
```

### Coverage by File

```bash
# Count lines per file
grep -E "^[[:space:]]*[0-9]+\|[[:space:]]*[0-9]+\|" coverage_report.txt | \
  awk -F'|' '{print $3}' | \
  awk '{print $1}' | \
  sort | uniq -c
```

## Improving Coverage

### Identify Uncovered Code

1. Run coverage script:
   ```bash
   ./scripts/coverage.sh
   ```

2. Check the report for lines with `0|` execution count:
   ```bash
   grep -E "^[[:space:]]*[0-9]+\|[[:space:]]*0\|" coverage_report.txt | head -20
   ```

3. Add tests for uncovered code paths

### Common Uncovered Areas

- Error handling paths
- Edge cases
- Fallback code paths
- Platform-specific code (iOS vs macOS)
- Private helper functions

## CI/CD Integration

Coverage is automatically checked in GitHub Actions on every push and pull request. The workflow:

1. Runs tests with coverage
2. Generates coverage report
3. Calculates coverage percentage
4. Fails if coverage is below 98%

See `.github/workflows/swift.yml` for details.

## Troubleshooting

### Script Not Executable

```bash
chmod +x scripts/coverage.sh
```

### No Coverage Data Found

Make sure tests were run with coverage:
```bash
swift test --enable-code-coverage
```

### Test Binary Not Found

The script tries multiple methods to find the test binary. If it fails:
1. Check that tests passed: `swift test`
2. Look for the binary manually: `find .build -name "*Tests" -type f`

### Architecture Issues

The script automatically detects architecture (arm64/x86_64). If you encounter issues:
- On Apple Silicon (M1/M2): uses `-arch arm64`
- On Intel Mac: uses `-arch x86_64`

## Additional Resources

- [LLVM Coverage Documentation](https://clang.llvm.org/docs/SourceBasedCodeCoverage.html)
- [Swift Testing Framework](https://developer.apple.com/documentation/testing)
- [GitHub Actions Workflow](.github/workflows/swift.yml)

