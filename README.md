# Composer

Companion to [DataPoints](../macreader/) — the workbench where promoted research material gets arranged into threads, outlines, and drafts.

See [COMPOSER_ARCHITECTURE.md](COMPOSER_ARCHITECTURE.md) for the full plan.

## Status

Phase 1: ingest + library. Items can be pushed into `/v1/ingest/items` (idempotent on `source + source_ref`), listed/filtered/searched through `/items`, archived and deleted. The web UI is a two-pane library: list on the left, detail on the right.

## Quick start

```bash
make setup                  # one-time: venv + npm install
make backend                # terminal 1: uvicorn on :5006
make web                    # terminal 2: vite on :3001
./scripts/seed_fixtures.sh  # optional: seed 5 sample items for testing
```

Open <http://localhost:3001>. The header shows a green dot when the backend is healthy.

## Mac app

Builds from the command line with SwiftPM — no Xcode app, no xcodegen:

```bash
make app                                 # release, host arch, ad-hoc signed
make app-run                             # ...and launch it
./scripts/build-mac-app.sh --universal   # arm64 + x86_64
./scripts/build-mac-app.sh --sign "Apple Development: you@example.com (TEAMID)"
```

Output lands in `app/Composer/builds/Composer.app`. The script bakes the repo
path it built from into the bundle, so the app finds this clone's `venv/` and
`backend/` on whatever machine built it. `app/Composer/project.yml` (xcodegen)
still works for opening the same sources in Xcode; both read bundle metadata
from that file.

## API

Public (consumed by DataPoints, guarded by `X-Ingest-Key`):

```
POST /v1/ingest/items          idempotent on (source, source_ref)
POST /v1/ingest/items/batch    same, array payload
GET  /v1/health                public
```

Internal (consumed by the web UI, guarded by `X-API-Key`):

```
GET    /items?q=&archived=&limit=&offset=
GET    /items/{id}
PATCH  /items/{id}             body: { archived: true | false }
DELETE /items/{id}
```

## Layout

```
backend/
  config.py           env + shared app state
  database.py         sqlite + schema (items + FTS5)
  auth.py             X-API-Key + X-Ingest-Key guards
  schemas.py          pydantic models
  repositories/       thin SQL wrappers
  routes/             fastapi routers (health, ingest, items)
  server.py           app factory, lifespan, CORS
web/
  src/
    lib/api.ts        typed fetch client
    components/       Library (list + detail panes)
scripts/
  seed_fixtures.sh    5 sample items via curl
data/                 sqlite lives here (gitignored)
```

## Auth

Two keys, both optional in dev (unset = open):

- `AUTH_API_KEY` — frontend → backend (`/items/*`)
- `COMPOSER_INGEST_KEY` — DataPoints → Composer (`/v1/ingest/*`)

Copy `.env.example` to `.env` to set them.
