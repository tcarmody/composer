# Composer backend — FastAPI served by uvicorn.
FROM python:3.12-slim

# curl is used by the container/platform health check; lxml/trafilatura ship
# manylinux wheels for cp312 so no compiler toolchain is needed.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install deps first so the layer caches across code changes.
COPY requirements.txt ./
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# Application code (the importable `backend` package).
COPY backend ./backend

# SQLite lives on a Railway Volume mounted at /data (see railway.json).
ENV DB_PATH=/data/composer.db \
    PYTHONUNBUFFERED=1

# Reported by /v1/health so the Mac client can detect a stale backend.
# Railway can pass the real SHA: --build-arg COMPOSER_BACKEND_COMMIT=$RAILWAY_GIT_COMMIT_SHA
ARG COMPOSER_BACKEND_COMMIT=unknown
ENV COMPOSER_BACKEND_COMMIT=${COMPOSER_BACKEND_COMMIT}

EXPOSE 5006

# Railway injects $PORT; bind 0.0.0.0 so the service is reachable. Falls back
# to 5006 for plain `docker run`.
CMD ["sh", "-c", "uvicorn backend.server:app --host 0.0.0.0 --port ${PORT:-5006}"]
