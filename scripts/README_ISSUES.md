# Creating GitHub Issues

This script helps create GitHub issues from the ROADMAP.md file.

## Prerequisites

1. GitHub Personal Access Token with `repo` scope
2. Repository access (emvakar/EKNetwork)

## Usage

### Option 1: Using Environment Variable

```bash
export GITHUB_TOKEN="your_github_token_here"
./scripts/create_issues.sh
```

### Option 2: Using Command Line Argument

```bash
./scripts/create_issues.sh "your_github_token_here"
```

### Option 3: Using SSH Key (via GitHub CLI)

If you have GitHub CLI installed:

```bash
gh auth login
gh issue create --title "[BUG] Memory Leak in ProgressDelegate" --body-file issue_template.txt
```

## What the Script Creates

The script creates the following issues:

### High Priority Issues
1. Memory Leak in ProgressDelegate
2. Force Unwrap in MultipartFormData

### Medium Priority Issues
3. Race Condition in updateBaseURL
4. Unsafe String(describing:) Usage in RetryPolicy
5. Missing Task Cancellation Handling in Retry Logic

### Improvements
6. Shared URLSession for Progress Tracking
7. Task Cancellation Support
8. Improved Error Handling in RetryPolicy
9. Metrics and Monitoring

## Manual Issue Creation

For low-priority issues, you can create them manually using the templates:

1. Go to https://github.com/emvakar/EKNetwork/issues/new
2. Select appropriate template:
   - Bug Report
   - Feature Request
   - Improvement

## Notes

- The script uses GitHub API v3
- Issues are created with appropriate labels
- Check ROADMAP.md for full details on each issue

