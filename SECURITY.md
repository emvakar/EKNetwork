# Security Policy

## Supported Versions

We release patches for security vulnerabilities. Which versions are eligible for receiving such patches depends on the CVSS v3.0 Rating:

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

Please report (suspected) security vulnerabilities to **security@eknetwork.dev**. You will receive a response within 48 hours. If the issue is confirmed, we will release a patch as soon as possible depending on complexity but historically within a few days.

Please include the following information in your report:

- Type of issue (e.g. buffer overflow, SQL injection, cross-site scripting, etc.)
- Full paths of source file(s) related to the manifestation of the issue
- The location of the affected source code (tag/branch/commit or direct URL)
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit the issue

This information will help us triage your report more quickly.

## Security Best Practices

When using EKNetwork, please follow these security best practices:

1. **Always use HTTPS** for production API calls
2. **Validate and sanitize** all user inputs before sending requests
3. **Store tokens securely** using Keychain or secure storage mechanisms
4. **Implement proper error handling** to avoid exposing sensitive information
5. **Keep dependencies updated** to the latest secure versions
6. **Use certificate pinning** for critical API endpoints when appropriate
7. **Implement rate limiting** to prevent abuse
8. **Log security events** for monitoring and auditing

## Disclosure Policy

When we receive a security bug report, we will assign it to a primary handler. This person will coordinate the fix and release process, involving the following steps:

1. Confirm the problem and determine the affected versions
2. Audit code to find any potential similar problems
3. Prepare fixes for all releases still under maintenance
4. Publish security advisories

We follow a coordinated disclosure process. We will notify you when we've received your report and keep you updated on our progress.

## Recognition

We appreciate responsible disclosure of security vulnerabilities. With your permission, we will acknowledge your contribution in our security advisories.

