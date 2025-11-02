#!/bin/bash

# Enhanced release script with support for major/minor/patch, auto-commit, and GitLab integration
# Usage:
#   ./scripts/release.sh patch          # Increment patch version (1.1.2 -> 1.1.3)
#   ./scripts/release.sh minor         # Increment minor version (1.1.2 -> 1.2.0)
#   ./scripts/release.sh major         # Increment major version (1.1.2 -> 2.0.0)
#   ./scripts/release.sh 1.2.0         # Use specific version
#   ./scripts/release.sh dev            # Commit changes locally (no release)
#   ./scripts/release.sh commit-push    # Commit and push changes (no release)
#   ./scripts/release.sh debug          # Show debug information (no changes)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$PROJECT_ROOT/Sources/EKNetwork/Version.swift"

# Function to print error and exit
error() {
    echo -e "${RED}Error:${NC} $1" >&2
    exit 1
}

# Function to print success message
success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Function to print info message
info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Function to print step message
step() {
    echo -e "${BLUE}→${NC} $1"
}

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "Not a git repository"
fi

# Load GitLab configuration from file if exists
if [ -f "$PROJECT_ROOT/.gitlab-release.env" ]; then
    source "$PROJECT_ROOT/.gitlab-release.env"
fi

# Get git remote info
REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
GITLAB_TOKEN="${GITLAB_TOKEN:-}"
GITLAB_API_URL="${GITLAB_API_URL:-}"

# Helper function to commit changes
commit_changes() {
    local commit_message="$1"
    local push_remote="${2:-false}"
    
    # Check if there are changes to commit
    if git diff --quiet HEAD -- && git diff --cached --quiet; then
        info "No changes to commit"
        return 0
    fi
    
    # Stage all changes
    git add -A
    
    # Check if there are staged changes
    if git diff --cached --quiet; then
        info "No changes staged for commit"
        return 0
    fi
    
    # Commit changes
    step "Committing changes: $commit_message"
    git commit -m "$commit_message"
    success "Changes committed"
    
    # Push if requested
    if [ "$push_remote" = "true" ]; then
        step "Pushing to remote..."
        CURRENT_BRANCH=$(git branch --show-current)
        git push origin "$CURRENT_BRANCH"
        success "Changes pushed to remote"
    fi
    
    return 0
}

# Helper function to generate changelog from git commits
generate_changelog() {
    local previous_tag="$1"
    local current_tag="$2"
    
    step "Generating changelog..."
    
    # Get commits between tags
    local commits
    if [ -z "$previous_tag" ]; then
        # If no previous tag, get all commits up to current tag
        commits=$(git log "$current_tag" --pretty=format:"- %s" --no-merges 2>/dev/null || echo "")
    else
        commits=$(git log "${previous_tag}..$current_tag" --pretty=format:"- %s" --no-merges 2>/dev/null || echo "")
    fi
    
    if [ -z "$commits" ]; then
        commits="- No commits found"
    fi
    
    # Create changelog
    local changelog="## Changes in ${current_tag}

$commits

"
    
    echo "$changelog"
}

# Helper function to create GitLab release
create_gitlab_release() {
    local tag_name="$1"
    local version="$2"
    local changelog="$3"
    
    # Check if GitLab is configured
    if [ -z "$GITLAB_TOKEN" ] && [ -z "$GITLAB_API_URL" ]; then
        # Try to detect GitLab from remote URL
        if [[ "$REMOTE_URL" == *"gitlab"* ]] || [[ "$REMOTE_URL" == *"gitlab.com"* ]] || [[ "$REMOTE_URL" == *"gitlab.eskaria.com"* ]]; then
            # Extract GitLab URL and project path
            if [[ "$REMOTE_URL" =~ git@([^:]+):(.+)\.git ]] || [[ "$REMOTE_URL" =~ https?://([^/]+)/(.+)\.git ]]; then
                if [ -z "$GITLAB_API_URL" ]; then
                    if [[ "$REMOTE_URL" =~ git@([^:]+):(.+)\.git ]]; then
                        GITLAB_HOST="${BASH_REMATCH[1]}"
                        PROJECT_PATH="${BASH_REMATCH[2]}"
                        GITLAB_API_URL="https://${GITLAB_HOST}/api/v4"
                    elif [[ "$REMOTE_URL" =~ https?://([^/]+)/(.+)\.git ]]; then
                        GITLAB_HOST="${BASH_REMATCH[1]}"
                        PROJECT_PATH="${BASH_REMATCH[2]}"
                        GITLAB_API_URL="https://${GITLAB_HOST}/api/v4"
                    fi
                fi
                
                # URL encode project path
                PROJECT_PATH_ENCODED=$(echo "$PROJECT_PATH" | sed 's/\//%2F/g')
            fi
        else
            info "GitLab not detected or not configured. Skipping release creation."
            info "To enable GitLab releases, set GITLAB_TOKEN and optionally GITLAB_API_URL"
            return 0
        fi
    fi
    
    if [ -z "$GITLAB_TOKEN" ]; then
        info "GITLAB_TOKEN not set. Skipping GitLab release creation."
        info "Set GITLAB_TOKEN environment variable to enable GitLab releases."
        return 0
    fi
    
    if [ -z "$GITLAB_API_URL" ]; then
        GITLAB_API_URL="https://gitlab.com/api/v4"
    fi
    
    step "Creating GitLab release for $tag_name..."
    
    # Get project ID if needed (can also use project path)
    local project_id_or_path="${PROJECT_PATH_ENCODED:-$(basename "$PROJECT_ROOT")}"
    
    # Create release via GitLab API
    local response
    response=$(curl -s -w "\n%{http_code}" \
        --request POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{
            \"name\": \"Release $version\",
            \"tag_name\": \"$tag_name\",
            \"description\": $(echo "$changelog" | jq -Rs .),
            \"released_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
        }" \
        "${GITLAB_API_URL}/projects/${project_id_or_path}/releases" 2>/dev/null || echo "")
    
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n-1)
    
    if [ "$http_code" -eq 201 ] || [ "$http_code" -eq 200 ]; then
        success "GitLab release created successfully"
    else
        info "Failed to create GitLab release (HTTP $http_code): $response_body"
        info "You can create it manually in GitLab UI"
    fi
}

# Helper function to show debug information
show_debug_info() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  EKNetwork Release Script - Debug Information${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Current directory
    step "Project Root:"
    echo "  $PROJECT_ROOT"
    echo ""
    
    # Git information
    step "Git Information:"
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
    echo "  Branch: $CURRENT_BRANCH"
    REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null || echo "not configured")
    echo "  Remote URL: $REMOTE_URL"
    
    # Latest tag
    latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [ -n "$latest_tag" ]; then
        latest_version="${latest_tag#v}"
        echo "  Latest tag: $latest_tag"
        echo "  Latest version: $latest_version"
        
        if [[ "$latest_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            IFS='.' read -r major minor patch <<< "$latest_version"
            echo ""
            step "Version Increment Preview:"
            echo "  Patch:  $latest_version -> $major.$minor.$((patch + 1))"
            echo "  Minor:  $latest_version -> $major.$((minor + 1)).0"
            echo "  Major:  $latest_version -> $((major + 1)).0.0"
        fi
    else
        echo "  Latest tag: (no tags found)"
    fi
    echo ""
    
    # Version.swift information
    step "Version.swift:"
    if [ -f "$VERSION_FILE" ]; then
        current_version=$(grep -o 'let EKNetworkVersionString = "[^"]*"' "$VERSION_FILE" | sed 's/.*"\(.*\)"/\1/' || echo "not found")
        echo "  Current version: $current_version"
        echo "  File path: $VERSION_FILE"
    else
        echo "  Status: File not found!"
        echo "  Expected: $VERSION_FILE"
    fi
    echo ""
    
    # Uncommitted changes
    step "Uncommitted Changes:"
    if git diff --quiet HEAD -- 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
        success "No uncommitted changes"
    else
        info "Uncommitted changes found:"
        git status --short | sed 's/^/  /'
        echo ""
        info "Changed files:"
        git diff --name-only | sed 's/^/  - /'
        if git diff --cached --quiet 2>/dev/null; then
            echo ""
            info "Staged files:"
            git diff --cached --name-only | sed 's/^/  - /'
        fi
    fi
    echo ""
    
    # Unpushed commits
    step "Unpushed Commits:"
    if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "unknown" ]; then
        unpushed=$(git log origin/"$CURRENT_BRANCH"..HEAD --oneline 2>/dev/null || echo "")
        if [ -n "$unpushed" ]; then
            echo "$unpushed" | sed 's/^/  /'
        else
            success "All commits are pushed"
        fi
    else
        info "Cannot determine branch"
    fi
    echo ""
    
    # GitLab configuration
    step "GitLab Configuration:"
    if [ -f "$PROJECT_ROOT/.gitlab-release.env" ]; then
        echo "  Config file: $PROJECT_ROOT/.gitlab-release.env (found)"
        if [ -n "$GITLAB_TOKEN" ]; then
            token_preview="${GITLAB_TOKEN:0:8}...${GITLAB_TOKEN: -4}"
            success "  GITLAB_TOKEN: Set (${token_preview})"
        else
            echo "  GITLAB_TOKEN: Not set"
        fi
        if [ -n "$GITLAB_API_URL" ]; then
            success "  GITLAB_API_URL: $GITLAB_API_URL"
        else
            echo "  GITLAB_API_URL: Not set (will auto-detect)"
        fi
    else
        echo "  Config file: Not found"
        echo "  Example: $PROJECT_ROOT/.gitlab-release.env.example"
    fi
    
    # Check if GitLab can be detected
    if [[ "$REMOTE_URL" == *"gitlab"* ]] || [[ "$REMOTE_URL" == *"gitlab.com"* ]] || [[ "$REMOTE_URL" == *"gitlab.eskaria.com"* ]]; then
        echo "  GitLab: Detected from remote URL"
    else
        echo "  GitLab: Not detected in remote URL"
    fi
    echo ""
    
    # Recent commits
    step "Recent Commits (last 5):"
    git log -5 --oneline --decorate 2>/dev/null | sed 's/^/  /' || echo "  (no commits)"
    echo ""
    
    # Git tags (last 5)
    step "Recent Tags (last 5):"
    git tag --sort=-creatordate | head -5 | sed 's/^/  /' || echo "  (no tags)"
    echo ""
    
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    info "Debug mode: No changes were made"
    echo ""
}

# Get the latest tag
latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

# Handle special modes
if [ "$1" = "debug" ]; then
    show_debug_info
    exit 0
fi

if [ "$1" = "dev" ]; then
    # Dev mode: commit changes locally without releasing
    step "Dev mode: committing changes locally..."
    
    if [ -z "$(git status --porcelain)" ]; then
        info "No changes to commit"
        exit 0
    fi
    
    # Generate commit message from changes
    commit_msg=$(git diff --name-only | head -3 | sed 's/^/- /' | tr '\n' ' ')
    if [ -z "$commit_msg" ]; then
        commit_msg="WIP: Development changes"
    else
        commit_msg="WIP: ${commit_msg}"
    fi
    
    commit_changes "$commit_msg" false
    success "Dev changes committed locally"
    exit 0
fi

if [ "$1" = "commit-push" ]; then
    # Commit and push mode: commit changes and push, no release
    step "Commit and push mode..."
    
    if [ -z "$(git status --porcelain)" ]; then
        info "No changes to commit"
        exit 0
    fi
    
    # Generate commit message from changes
    commit_msg=$(git diff --name-only | head -3 | sed 's/^/- /' | tr '\n' ' ')
    if [ -z "$commit_msg" ]; then
        commit_msg="Update: Development changes"
    else
        commit_msg="Update: ${commit_msg}"
    fi
    
    commit_changes "$commit_msg" true
    success "Changes committed and pushed"
    exit 0
fi

# Determine new version based on mode
if [ -z "$1" ]; then
    # Default to patch
    VERSION_MODE="patch"
elif [ "$1" = "patch" ] || [ "$1" = "minor" ] || [ "$1" = "major" ]; then
    VERSION_MODE="$1"
elif [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # Specific version provided
    new_version="$1"
    VERSION_MODE="specific"
else
    error "Invalid argument: $1\nUsage: ./scripts/release.sh [patch|minor|major|dev|commit-push|<version>]"
fi

# Calculate new version based on mode
if [ "$VERSION_MODE" != "specific" ]; then
    if [ -z "$latest_tag" ]; then
        error "No git tags found. Please provide initial version (e.g., 1.0.0)"
    fi
    
    # Remove 'v' prefix if present
    latest_version="${latest_tag#v}"
    
    # Validate version format
    if ! [[ "$latest_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error "Latest tag '$latest_tag' is not in semver format (X.Y.Z)"
    fi
    
    # Parse version components
    IFS='.' read -r major minor patch <<< "$latest_version"
    
    # Increment based on mode
    case "$VERSION_MODE" in
        patch)
            patch=$((patch + 1))
            new_version="$major.$minor.$patch"
            info "Latest version: $latest_version"
            info "Incrementing patch version: $new_version"
            ;;
        minor)
            patch=0
            minor=$((minor + 1))
            new_version="$major.$minor.$patch"
            info "Latest version: $latest_version"
            info "Incrementing minor version: $new_version"
            ;;
        major)
            patch=0
            minor=0
            major=$((major + 1))
            new_version="$major.$minor.$patch"
            info "Latest version: $latest_version"
            info "Incrementing major version: $new_version"
            ;;
    esac
fi

# Check if tag already exists
tag_name="v$new_version"
if git rev-parse "$tag_name" >/dev/null 2>&1; then
    error "Tag $tag_name already exists"
fi

# Commit any uncommitted changes before release
if ! git diff-index --quiet HEAD -- || ! git diff --cached --quiet; then
    step "Found uncommitted changes, committing them..."
    
    # Generate smart commit message from changes
    changed_files=$(git diff --name-only | head -5 | tr '\n' ' ')
    commit_message="Prepare release $new_version: $changed_files"
    
    commit_changes "$commit_message" false
fi

# Update Version.swift
step "Updating Version.swift..."
if [ ! -f "$VERSION_FILE" ]; then
    error "Version.swift not found at $VERSION_FILE"
fi

# Create backup
cp "$VERSION_FILE" "$VERSION_FILE.bak"

# Update version in Version.swift (macOS/BSD sed)
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/let EKNetworkVersionString = \".*\"/let EKNetworkVersionString = \"$new_version\"/" "$VERSION_FILE"
else
    sed -i "s/let EKNetworkVersionString = \".*\"/let EKNetworkVersionString = \"$new_version\"/" "$VERSION_FILE"
fi

# Verify the update
if ! grep -q "let EKNetworkVersionString = \"$new_version\"" "$VERSION_FILE"; then
    mv "$VERSION_FILE.bak" "$VERSION_FILE"
    error "Failed to update Version.swift"
fi

success "Version.swift updated to $new_version"

# Commit Version.swift change
step "Committing version update..."
git add "$VERSION_FILE"
git commit -m "Bump version to $new_version" > /dev/null 2>&1 || {
    info "Version.swift already at $new_version (no commit needed)"
}

# Remove backup file
rm -f "$VERSION_FILE.bak"

# Create git tag
step "Creating git tag: $tag_name"

# Generate changelog for tag message
previous_tag="$latest_tag"
changelog=$(generate_changelog "$previous_tag" "$tag_name")
tag_message="Release version $new_version

$changelog"

git tag -a "$tag_name" -m "$tag_message"
success "Git tag $tag_name created"

# Push everything
step "Pushing to remote..."
CURRENT_BRANCH=$(git branch --show-current)
git push origin "$CURRENT_BRANCH"
git push origin "$tag_name"
success "Pushed to remote"

# Create GitLab release if configured
create_gitlab_release "$tag_name" "$new_version" "$changelog"

echo ""
success "Release process completed!"
info "Version: $new_version"
info "Tag: $tag_name"
echo ""
