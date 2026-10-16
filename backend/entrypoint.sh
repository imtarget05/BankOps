#!/bin/sh
set -e

# Run migrations if DATABASE_URL is set
if [ -n "$DATABASE_URL" ]; then
    echo "[Entrypoint] Running database migrations (alembic upgrade head)..."
    alembic upgrade head || echo "[Entrypoint] WARNING: alembic upgrade head failed. Proceeding with server start..."
else
    echo "[Entrypoint] DATABASE_URL is not set. Skipping alembic upgrade head."
fi

echo "[Entrypoint] Starting Uvicorn on 0.0.0.0:${PORT:-8000}..."
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}"
