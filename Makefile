.PHONY: setup backend web dev test clean app app-run app-test

# Interpreter for the venv. The backend needs 3.10+ (uvicorn>=0.40), but macOS's
# /usr/bin/python3 is 3.9, so don't trust plain python3. Prefer 3.14 to match
# the Dockerfile, then any other 3.10+. Homebrew's bin dirs are searched too,
# since non-login shells (IDEs, GUI launchers) often lack them on PATH. Resolves
# to an absolute path. Override: make setup PYTHON=/path/to/python3
PYTHON_CANDIDATES := python3.14 python3.15 python3.13 python3.12 python3.11 python3.10 python3
PYTHON ?= $(shell PATH="$$PATH:/opt/homebrew/bin:/usr/local/bin"; \
	for p in $(PYTHON_CANDIDATES); do \
	path=$$(command -v $$p 2>/dev/null) && \
	"$$path" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null && \
	{ echo "$$path"; break; }; done)

# One-time setup: Python venv + npm install
setup:
	@[ -n "$(PYTHON)" ] || { echo "error: no Python 3.10+ found (tried: $(PYTHON_CANDIDATES)). Install one, e.g. 'brew install python@3.14', or pass PYTHON=/path/to/python3." >&2; exit 1; }
	@echo "Using $(PYTHON) ($$($(PYTHON) --version))"
	$(PYTHON) -m venv venv
	./venv/bin/pip install --upgrade pip
	./venv/bin/pip install -r requirements.txt
	cd web && npm install
	mkdir -p data
	@echo "Setup complete. Copy .env.example to .env if you want auth, then 'make dev'."

# Run backend only
backend:
	./venv/bin/python -m uvicorn backend.server:app --reload --port 5006

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
	./venv/bin/python -m pytest backend/tests/ -v

# Build + sign the Mac app (no Xcode needed). CODESIGN_IDENTITY overrides ad-hoc.
app:
	./scripts/build-mac-app.sh

# Same, then launch it
app-run:
	./scripts/build-mac-app.sh --run

# Mac app unit tests (also runnable in Xcode via the Composer scheme)
app-test:
	swift test --package-path app/Composer

# Typecheck + build frontend
check:
	cd web && npm run typecheck && npm run build

clean:
	rm -rf venv web/node_modules web/dist data/composer.db
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
