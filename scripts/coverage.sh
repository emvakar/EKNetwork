#!/bin/bash

# Script to generate and display code coverage report
# This script is designed to work both locally and in CI environments

set -e

echo "🔍 Generating code coverage report..."

# Run tests with coverage if not already done
if [ ! -f .build/*/debug/codecov/default.profdata ] && [ -z "$(find .build -name "*.profdata" 2>/dev/null | head -1)" ]; then
    echo "📦 Running tests with coverage..."
    swift test --enable-code-coverage
fi

# Find the profdata file
PROFDATA=$(find .build -name "*.profdata" 2>/dev/null | head -1)

if [ -z "$PROFDATA" ]; then
    echo "❌ No coverage data found"
    echo "Searching for profdata files:"
    find .build -name "*.profdata" 2>/dev/null || echo "No profdata files found"
    exit 1
fi

echo "📊 Coverage data found: $PROFDATA"

# Find the test binary
TEST_BINARY=""

# Method 1: Try xctest bundle (most common in SPM)
TEST_BINARY=$(find .build -path "*/EKNetworkPackageTests.xctest/Contents/MacOS/EKNetworkPackageTests" 2>/dev/null | head -1)

# Method 2: Try direct binary
if [ -z "$TEST_BINARY" ]; then
    TEST_BINARY=$(find .build -name "*PackageTests" -type f -perm +111 2>/dev/null | grep -v ".dSYM" | head -1)
fi

# Method 3: Try any test binary
if [ -z "$TEST_BINARY" ]; then
    TEST_BINARY=$(find .build -name "*Tests" -type f -perm +111 2>/dev/null | grep -v ".dSYM" | head -1)
fi

if [ -z "$TEST_BINARY" ]; then
    echo "❌ Test binary not found"
    echo "Searching for test binaries:"
    find .build -type f -perm +111 2>/dev/null | head -10 || echo "No test binaries found"
    exit 1
fi

echo "🧪 Test binary found: $TEST_BINARY"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    ARCH_FLAG="-arch arm64"
else
    ARCH_FLAG="-arch x86_64"
fi

# Generate coverage report
echo "📈 Generating coverage report..."
           xcrun llvm-cov show \
               -instr-profile "$PROFDATA" \
               "$TEST_BINARY" \
               $ARCH_FLAG \
               -format=text \
               -ignore-filename-regex=".*Tests.*|.*Version\.swift|.*EKNetworkVersion\.swift|.*ProgressSessionManager\.swift" \
               > coverage_report.txt 2>&1 || {
    echo "⚠️ Coverage report generation had issues"
    echo "Trying without architecture flag..."
               xcrun llvm-cov show \
                   -instr-profile "$PROFDATA" \
                   "$TEST_BINARY" \
                   -format=text \
                   -ignore-filename-regex=".*Tests.*|.*Version\.swift|.*EKNetworkVersion\.swift|.*ProgressSessionManager\.swift" \
                   > coverage_report.txt 2>&1 || {
        echo "❌ Failed to generate coverage report"
        exit 1
    }
}

# Calculate coverage
if [ ! -f coverage_report.txt ]; then
    echo "❌ Coverage report file not created"
    exit 1
fi

# llvm-cov format: "    line_number|execution_count|code"
# Count lines with execution data (lines that have |)
TOTAL_LINES=$(grep -E "^[[:space:]]*[0-9]+\|[[:space:]]*[0-9]+\|" coverage_report.txt 2>/dev/null | wc -l | tr -d ' ' || echo "0")
# Count covered lines (execution count > 0)
COVERED_LINES=$(grep -E "^[[:space:]]*[0-9]+\|[[:space:]]*[1-9][0-9]*\|" coverage_report.txt 2>/dev/null | wc -l | tr -d ' ' || echo "0")

if [ "$TOTAL_LINES" -eq 0 ]; then
    echo "⚠️ Could not calculate coverage (no lines found in report)"
    echo "First 20 lines of report:"
    head -20 coverage_report.txt || true
    exit 1
fi

# Calculate percentage using awk for better precision
COVERAGE=$(awk "BEGIN {printf \"%.2f\", ($COVERED_LINES * 100) / $TOTAL_LINES}")
COVERAGE_INT=$(echo "$COVERAGE" | cut -d. -f1)

echo ""
echo "✅ Code Coverage Report"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Total lines:     $TOTAL_LINES"
echo "Covered lines:   $COVERED_LINES"
echo "Coverage:        ${COVERAGE}%"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$COVERAGE_INT" -ge 98 ]; then
    echo "✅ Coverage meets 98% requirement"
    exit 0
else
    echo "❌ Coverage is ${COVERAGE}%, but required minimum is 98%"
    exit 1
fi
