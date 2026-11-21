.PHONY: setup backend web dev test clean app app-run app-test check

# One-time setup. uv installs the Python in .python-version (3.14) into .venv
# itself, so the system python3 doesn't matter. Install uv once with
# `brew install uv`. web/ needs npm; the Mac app doesn't.
setup:
	uv sync
	@if command -v npm >/dev/null 2>&1; then cd web && npm install; \
	else echo "npm not found: skipping web/ (only the web frontend needs it)"; fi
	mkdir -p data
	@echo "Setup complete. Copy .env.example to .env if you want auth, then 'make dev'."

# Run backend only
backend:
	uv run uvicorn backend.server:app --reload --port 5006

# Run frontend only
web:
	cd web && npm run dev

# Run both (needs two terminals or a process manager — this just prints help)
dev:
	@echo "Run these in two terminals:"
	@echo "  make backend"
	@echo "  make web"

# Run backend tests
test:
	uv run pytest backend/tests/ -v

# Build + sign the Mac app (no Xcode needed), with dpcommon-macapp from the
# shared package; config is [tool.dpcommon.macapp] in pyproject.toml.
# CODESIGN_IDENTITY picks the signing identity.
app:
	uv run dpcommon-macapp app

# Same, then launch it
app-run:
	uv run dpcommon-macapp app --run

# Mac app unit tests (also runnable in Xcode via the Composer scheme)
app-test:
	swift test --package-path app/Composer

# Typecheck + build frontend
check:
	cd web && npm run typecheck && npm run build

clean:
	rm -rf .venv venv web/node_modules web/dist data/composer.db
	find . -type d -name "__pycache__" -not -path "./.venv/*" -exec rm -rf {} + 2>/dev/null || true
