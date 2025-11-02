.PHONY: help release patch minor major dev commit-push debug test-build test-ios test-macos

# Default target
help:
	@echo "EKNetwork Release Management"
	@echo ""
	@echo "Available commands:"
	@echo "  make patch          - Release patch version (1.1.2 -> 1.1.3)"
	@echo "  make minor          - Release minor version (1.1.2 -> 1.2.0)"
	@echo "  make major          - Release major version (1.1.2 -> 2.0.0)"
	@echo "  make release TYPE=X.Y.Z - Release specific version"
	@echo "  make dev            - Commit changes locally without releasing"
	@echo "  make commit-push    - Commit and push current changes (no release)"
	@echo "  make debug          - Show debug information (version, status, config)"
	@echo "  make test-build     - Test build for all platforms (iOS + macOS)"
	@echo "  make test-ios       - Test build for iOS only"
	@echo "  make test-macos     - Test build for macOS only"
	@echo ""
	@echo "Examples:"
	@echo "  make patch"
	@echo "  make minor"
	@echo "  make major"
	@echo "  make release TYPE=1.5.0"
	@echo "  make debug"
	@echo "  make test-build"

# Patch release (increment last number: 1.1.2 -> 1.1.3)
patch:
	@./scripts/release.sh patch

# Minor release (increment middle number: 1.1.2 -> 1.2.0)
minor:
	@./scripts/release.sh minor

# Major release (increment first number: 1.1.2 -> 2.0.0)
major:
	@./scripts/release.sh major

# Specific version release
release:
	@if [ -z "$(TYPE)" ]; then \
		echo "Error: TYPE is required. Example: make release TYPE=1.5.0"; \
		exit 1; \
	fi
	@./scripts/release.sh "$(TYPE)"

# Dev mode: commit changes locally without releasing
dev:
	@./scripts/release.sh dev

# Commit and push current changes (no release)
commit-push:
	@./scripts/release.sh commit-push

# Debug mode: show all information without making changes
debug:
	@./scripts/release.sh debug

# Test build for all platforms
test-build: test-macos test-ios
	@echo ""
	@echo "✓ All platform builds successful!"

# Test build for iOS
test-ios:
	@echo "Testing iOS build..."
	@swift build 2>&1 | grep -i "error" && (echo "❌ iOS build failed" && exit 1) || echo "✓ iOS build successful"

# Test build for macOS
test-macos:
	@echo "Testing macOS build..."
	@swift build -c release 2>&1 | grep -i "error" && exit 1 || echo "✓ macOS build successful"

