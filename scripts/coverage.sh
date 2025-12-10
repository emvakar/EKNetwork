#!/bin/bash

# Script to generate and display code coverage report

set -e

echo "🔍 Generating code coverage report..."

# Run tests with coverage
swift test --enable-code-coverage

# Find the profdata file
PROFDATA=$(find .build -name "*.profdata" | head -1)

if [ -z "$PROFDATA" ]; then
    echo "❌ No coverage data found"
    exit 1
fi

echo "📊 Coverage data found: $PROFDATA"

# Find the test binary
TEST_BINARY=$(find .build -name "*Tests" -type f -perm +111 | grep -v ".dSYM" | head -1)

if [ -z "$TEST_BINARY" ]; then
    echo "⚠️  Test binary not found, trying alternative method..."
    # Try to find xctest bundle
    TEST_BINARY=$(find .build -path "*/EKNetworkPackageTests.xctest/Contents/MacOS/EKNetworkPackageTests" | head -1)
fi

if [ -z "$TEST_BINARY" ]; then
    echo "❌ Test binary not found"
    exit 1
fi

echo "🧪 Test binary found: $TEST_BINARY"

# Generate coverage report
echo "📈 Generating coverage report..."
xcrun llvm-cov show \
    -instr-profile "$PROFDATA" \
    "$TEST_BINARY" \
    -arch arm64 \
    -format=text \
    -ignore-filename-regex=".*Tests.*" \
    > coverage_report.txt 2>/dev/null || true

# Calculate coverage
if [ -f coverage_report.txt ]; then
    TOTAL_LINES=$(grep -c "^.*:[0-9]" coverage_report.txt 2>/dev/null || echo "0")
    COVERED_LINES=$(grep -E "^.*:[0-9]+.*[1-9]" coverage_report.txt 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    
    if [ "$TOTAL_LINES" -gt 0 ]; then
        COVERAGE=$(echo "scale=2; $COVERED_LINES * 100 / $TOTAL_LINES" | bc)
        echo ""
        echo "✅ Code Coverage Report"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Total lines:     $TOTAL_LINES"
        echo "Covered lines:   $COVERED_LINES"
        echo "Coverage:        ${COVERAGE}%"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        if (( $(echo "$COVERAGE >= 98" | bc -l) )); then
            echo "✅ Coverage meets 98% requirement"
            exit 0
        else
            echo "❌ Coverage is ${COVERAGE}%, but required minimum is 98%"
            exit 1
        fi
    else
        echo "⚠️  Could not calculate coverage (no lines found)"
        exit 1
    fi
else
    echo "❌ Coverage report generation failed"
    exit 1
fi

