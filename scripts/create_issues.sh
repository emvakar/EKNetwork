#!/bin/bash

# Script to create GitHub issues from ROADMAP.md
# Usage: ./scripts/create_issues.sh [GITHUB_TOKEN]

set -e

GITHUB_TOKEN="${1:-${GITHUB_TOKEN}}"
REPO_OWNER="emvakar"
REPO_NAME="EKNetwork"
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GitHub token is required"
    echo "Usage: $0 <GITHUB_TOKEN>"
    echo "Or set GITHUB_TOKEN environment variable"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Creating GitHub issues from ROADMAP.md...${NC}"

# Function to create an issue
create_issue() {
    local title="$1"
    local body="$2"
    local labels="$3"
    
    local json=$(cat <<EOF
{
    "title": "$title",
    "body": "$body",
    "labels": [$labels]
}
EOF
)
    
    local response=$(curl -s -X POST "$API_URL" \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        -d "$json")
    
    local issue_number=$(echo "$response" | grep -o '"number":[0-9]*' | head -1 | cut -d':' -f2)
    
    if [ -n "$issue_number" ]; then
        echo -e "${GREEN}✓ Created issue #$issue_number: $title${NC}"
        echo "$issue_number"
    else
        echo -e "${RED}✗ Failed to create issue: $title${NC}"
        echo "$response" >&2
        echo ""
    fi
}

# High Priority Issues
echo -e "\n${YELLOW}Creating High Priority Issues...${NC}"

ISSUE1_BODY="## Problem
In lines 729-731, a new \`URLSession\` with \`ProgressDelegate\` is created for each request with progress. \`ProgressDelegate\` holds \`NetworkProgress\`, which may hold \`URLSession\`, creating a potential retain cycle.

## Location
\`NetworkManager.swift:729-731\`

## Solution
- Use a shared \`URLSession\` with a delegate manager
- Or explicitly invalidate session after request completion

## Priority
High - Memory leak can cause serious issues in production

## Related
See ROADMAP.md for full details"

create_issue "[BUG] Memory Leak in ProgressDelegate" "$ISSUE1_BODY" '"bug", "high-priority"'

ISSUE2_BODY="## Problem
Force unwrap (\`!\`) is used in lines 273, 275, 277, 279, 282 when converting strings to Data. This can cause crashes if conversion fails.

## Location
\`NetworkManager.swift:273-282\`

## Solution
- Use safe conversion with error handling
- Or use \`Data(contentsOf:)\` with validation

## Priority
Medium - Can cause crashes in edge cases

## Related
See ROADMAP.md for full details"

create_issue "[BUG] Force Unwrap in MultipartFormData" "$ISSUE2_BODY" '"bug", "medium-priority"'

# Medium Priority Issues
echo -e "\n${YELLOW}Creating Medium Priority Issues...${NC}"

# Issue #3 (Race Condition in updateBaseURL) — RESOLVED in v1.4.1: baseURL is now a closure, updateBaseURL removed.
# create_issue "[BUG] Race Condition in updateBaseURL" "$ISSUE3_BODY" '"bug", "medium-priority"'

ISSUE4_BODY="## Problem
In line 507, \`String(describing: type(of: \$0))\` is used for type checking. This is an unreliable way to check types.

## Location
\`NetworkManager.swift:507-509\`

## Solution
- Use protocols to mark errors that shouldn't be retried
- Or use \`is\` for type checking

## Priority
Medium - Type safety improvement

## Related
See ROADMAP.md for full details"

create_issue "[IMPROVEMENT] Unsafe String(describing:) Usage in RetryPolicy" "$ISSUE4_BODY" '"enhancement", "medium-priority"'

ISSUE5_BODY="## Problem
Retry logic doesn't check if Task was cancelled. This can lead to unnecessary retries after cancellation.

## Location
\`NetworkManager.swift:772-774\`

## Solution
- Add \`Task.isCancelled\` check before retry
- Throw \`CancellationError\` on cancellation

## Priority
Medium - Better resource management

## Related
See ROADMAP.md for full details"

create_issue "[IMPROVEMENT] Missing Task Cancellation Handling in Retry Logic" "$ISSUE5_BODY" '"enhancement", "medium-priority"'

# Improvements
echo -e "\n${YELLOW}Creating Improvement Issues...${NC}"

IMPROVEMENT1_BODY="## Description
Use a shared \`URLSession\` with delegate manager for all progress requests.

## Benefits
- Avoid memory leaks
- Better performance
- Centralized management

## Priority
High

## Related
See ROADMAP.md for full details"

create_issue "[IMPROVEMENT] Shared URLSession for Progress Tracking" "$IMPROVEMENT1_BODY" '"enhancement", "high-priority"'

IMPROVEMENT2_BODY="## Description
Add support for cancelling requests via \`Task\` cancellation.

## Benefits
- Better request control
- Resource savings
- Modern Swift practices compliance

## Priority
High

## Related
See ROADMAP.md for full details"

create_issue "[IMPROVEMENT] Task Cancellation Support" "$IMPROVEMENT2_BODY" '"enhancement", "high-priority"'

IMPROVEMENT3_BODY="## Description
Use protocols instead of string type name checking in RetryPolicy.

\`\`\`swift
protocol NonRetriableError: Error {}
\`\`\`

## Benefits
- Type safety
- Better performance
- Cleaner code

## Priority
Medium

## Related
See ROADMAP.md for full details"

create_issue "[IMPROVEMENT] Improved Error Handling in RetryPolicy" "$IMPROVEMENT3_BODY" '"enhancement", "medium-priority"'

IMPROVEMENT4_BODY="## Description
Add ability to track request metrics (execution time, data size, etc.).

## Benefits
- Better diagnostics
- Performance monitoring
- Problem debugging

## Priority
Medium

## Related
See ROADMAP.md for full details"

create_issue "[IMPROVEMENT] Metrics and Monitoring" "$IMPROVEMENT4_BODY" '"enhancement", "medium-priority"'

echo -e "\n${GREEN}Done! Check GitHub issues for created items.${NC}"
echo -e "${YELLOW}Note: Some low-priority issues were skipped. Create them manually if needed.${NC}"

