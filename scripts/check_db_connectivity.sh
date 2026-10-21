#!/bin/bash
# Check PostgreSQL connectivity for Alembic migrations
# Uses psql if available, otherwise falls back to bash TCP check

set -e

echo "Checking PostgreSQL connectivity..."

# Wait for PostgreSQL to be ready using pg_isready
if command -v pg_isready &> /dev/null; then
    echo "Using pg_isready to check PostgreSQL..."
    until pg_isready -h postgres -p 5432 -U bankops 2>/dev/null; do
        echo "PostgreSQL not ready yet, waiting..."
        sleep 2
    done
    echo "PostgreSQL is ready (pg_isready)"
else
    # Fall back to psql or bash TCP check
    echo "pg_isready not available, using alternative check..."
    until psql -h postgres -U bankops -d bankops_test -c 'SELECT 1;' > /dev/null 2>&1; do
        echo "PostgreSQL not ready yet, waiting..."
        sleep 2
    done
    echo "PostgreSQL is ready (psql)"
fi

echo "PostgreSQL connectivity check complete"
exit 0
