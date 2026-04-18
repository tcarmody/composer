.PHONY: setup backend web dev test clean

# One-time setup: Python venv + npm install
setup:
	python3 -m venv venv
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

# Typecheck + build frontend
check:
	cd web && npm run typecheck && npm run build

clean:
	rm -rf venv web/node_modules web/dist data/composer.db
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
