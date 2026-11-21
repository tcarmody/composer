# Composer backend — FastAPI served by uvicorn.
# Must match local dev (3.14): the codebase relies on PEP 649 deferred
# annotation evaluation, so annotations like list[tuple[MemberType, str]]
# only import cleanly on 3.14+. Older Pythons evaluate them eagerly and crash.
FROM python:3.14-slim

COPY --from=ghcr.io/astral-sh/uv:0.13.9 /uv /uvx /bin/

# curl is used by the container/platform health check; every dependency ships
# a cp314 manylinux wheel, so no compiler toolchain is needed.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Use the base image's interpreter (never download one), compile bytecode at
# install time for faster startup, and copy rather than hardlink from the cache.
ENV UV_PYTHON_DOWNLOADS=never \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# Install deps first so the layer caches across code changes.
# --frozen: install exactly uv.lock, failing if it's out of date with pyproject.
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --frozen --no-dev --no-install-project

# Application code (the importable `backend` package).
COPY backend ./backend

# SQLite lives on a Railway Volume mounted at /data (see railway.json).
ENV PATH="/app/.venv/bin:$PATH" \
    DB_PATH=/data/composer.db \
    PYTHONUNBUFFERED=1

# Reported by /v1/health so the Mac client can detect a stale backend.
# Railway can pass the real SHA: --build-arg COMPOSER_BACKEND_COMMIT=$RAILWAY_GIT_COMMIT_SHA
ARG COMPOSER_BACKEND_COMMIT=unknown
ENV COMPOSER_BACKEND_COMMIT=${COMPOSER_BACKEND_COMMIT}

EXPOSE 5006

# Railway injects $PORT; bind 0.0.0.0 so the service is reachable. Falls back
# to 5006 for plain `docker run`.
CMD ["sh", "-c", "uvicorn backend.server:app --host 0.0.0.0 --port ${PORT:-5006}"]
