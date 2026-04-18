# Composer

Companion to [DataPoints](../macreader/) — the workbench where promoted research material gets arranged into threads, outlines, and drafts.

See [COMPOSER_ARCHITECTURE.md](COMPOSER_ARCHITECTURE.md) for the full plan.

## Status

Phase 0: skeleton. FastAPI backend on port 5006, React+Vite frontend on port 3001, SQLite at `data/composer.db`. Exit criterion: frontend loads, backend responds to `GET /v1/health`.

## Quick start

```bash
make setup        # one-time: venv + npm install
make backend      # terminal 1: uvicorn on :5006
make web          # terminal 2: vite on :3001
```

Open <http://localhost:3001>. The header should show a green "backend ok" indicator.

## Layout

```
backend/
  config.py         env + shared app state
  database.py       sqlite + schema init
  auth.py           X-API-Key + X-Ingest-Key guards
  schemas.py        pydantic models
  routes/           fastapi routers
  server.py         app factory, lifespan, CORS
web/
  src/              react + vite + tailwind
data/               sqlite lives here (gitignored)
```

## Auth

Two keys, both optional in dev:

- `AUTH_API_KEY` — frontend → backend
- `COMPOSER_INGEST_KEY` — DataPoints → Composer (`/v1/ingest/*`, not yet implemented)

Copy `.env.example` to `.env` to set them.
