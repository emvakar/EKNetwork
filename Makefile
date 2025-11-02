.PHONY: help release patch minor major dev commit-push debug

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
	@echo ""
	@echo "Examples:"
	@echo "  make patch"
	@echo "  make minor"
	@echo "  make major"
	@echo "  make release TYPE=1.5.0"
	@echo "  make debug"

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

