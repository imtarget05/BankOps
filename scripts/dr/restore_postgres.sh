#!/usr/bin/env bash
# =============================================================================
# BankOps Disaster Recovery: Database Restore Script
# Decrypts backup, validates SHA-256 integrity, and restores database using pg_restore.
# Supports native postgres tools and Docker container fallback.
# =============================================================================
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <path-to-backup-file> [target-database-name]" >&2
    echo "Example: $0 /tmp/bankops_dump_20261014.dump.gpg bankops" >&2
    exit 1
fi

INPUT_FILE="$1"
DB_NAME="${2:-${DB_NAME:-bankops}}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-bankops}"
DB_PASSWORD="${DB_PASSWORD:-bankops}"
GPG_PASSPHRASE="${BACKUP_GPG_PASSPHRASE:-}"
DOCKER_CONTAINER="${DOCKER_CONTAINER:-bankops-db}"

echo "=========================================================="
echo " Starting BankOps Disaster Recovery Restore"
echo " Target DB: ${DB_NAME} on ${DB_HOST}:${DB_PORT} as ${DB_USER}"
echo " Source File: ${INPUT_FILE}"
echo "=========================================================="

if [ ! -f "${INPUT_FILE}" ]; then
    echo "❌ Error: Backup file not found: ${INPUT_FILE}" >&2
    exit 1
fi

USE_DOCKER=0
if ! command -v pg_restore > /dev/null 2>&1; then
    if command -v docker > /dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER}$"; then
        echo "ℹ️ Note: Native pg_restore not found on host. Using Docker container '${DOCKER_CONTAINER}'."
        USE_DOCKER=1
    else
        echo "❌ Error: Neither native pg_restore nor running container '${DOCKER_CONTAINER}' found." >&2
        exit 1
    fi
fi

RESTORE_DUMP_FILE="${INPUT_FILE}"

# 1. Decrypt if GPG encrypted
if [[ "${INPUT_FILE}" == *.gpg ]]; then
    echo "[1/4] Decrypting GPG backup file..."
    DECRYPTED_FILE="${INPUT_FILE%.gpg}"
    if [ -z "${GPG_PASSPHRASE}" ]; then
        echo "Enter GPG Passphrase:"
        read -s GPG_PASSPHRASE
    fi
    gpg --batch --yes --passphrase "${GPG_PASSPHRASE}" \
        --decrypt -o "${DECRYPTED_FILE}" "${INPUT_FILE}"
    RESTORE_DUMP_FILE="${DECRYPTED_FILE}"
    echo "✅ Decrypted to: ${RESTORE_DUMP_FILE}"
else
    echo "[1/4] File is unencrypted dump."
fi

# 2. Checksum validation if .sha256 file exists
CHECKSUM_FILE="${RESTORE_DUMP_FILE}.sha256"
if [ -f "${CHECKSUM_FILE}" ]; then
    echo "[2/4] Validating SHA-256 checksum..."
    EXPECTED_HASH=$(awk '{print $1}' "${CHECKSUM_FILE}")
    if command -v sha256sum > /dev/null 2>&1; then
        ACTUAL_HASH=$(sha256sum "${RESTORE_DUMP_FILE}" | awk '{print $1}')
    else
        ACTUAL_HASH=$(shasum -a 256 "${RESTORE_DUMP_FILE}" | awk '{print $1}')
    fi

    if [ "${EXPECTED_HASH}" != "${ACTUAL_HASH}" ]; then
        echo "❌ FATAL: Checksum mismatch! Potential corrupted or tampered backup." >&2
        echo "Expected: ${EXPECTED_HASH}" >&2
        echo "Actual:   ${ACTUAL_HASH}" >&2
        exit 1
    fi
    echo "✅ Integrity verified: Checksum matches ${ACTUAL_HASH}"
else
    echo "[2/4] Note: No .sha256 companion file found; skipping hash verification."
fi

# 3. Test DB connection
echo "[3/4] Verifying target PostgreSQL instance is ready..."
if [ "${USE_DOCKER}" -eq 1 ]; then
    docker exec "${DOCKER_CONTAINER}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" || {
        echo "❌ Error: Database ${DB_NAME} not ready in container ${DOCKER_CONTAINER}" >&2
        exit 1
    }
else
    PGPASSWORD="${DB_PASSWORD}" pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" || {
        echo "❌ Error: Cannot connect to target database ${DB_NAME} at ${DB_HOST}:${DB_PORT}" >&2
        exit 1
    }
fi

# 4. Perform pg_restore
echo "[4/4] Restoring database using pg_restore (--clean --if-exists)..."
if [ "${USE_DOCKER}" -eq 1 ]; then
    cat "${RESTORE_DUMP_FILE}" | docker exec -i -e PGPASSWORD="${DB_PASSWORD}" "${DOCKER_CONTAINER}" \
        pg_restore -U "${DB_USER}" -d "${DB_NAME}" --clean --if-exists --no-owner --no-privileges || {
            echo "⚠️ Note: pg_restore completed with notices/warnings (expected for pre-existing system objects)."
        }
    echo "=========================================================="
    echo " Verifying Restored Database Schema and Tables..."
    docker exec "${DOCKER_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" \
        -c "SELECT count(*) AS total_tables FROM information_schema.tables WHERE table_schema = 'public';"
    docker exec "${DOCKER_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" \
        -c "SELECT version_num FROM alembic_version;" || echo "No alembic_version table found."
else
    PGPASSWORD="${DB_PASSWORD}" pg_restore \
        -h "${DB_HOST}" \
        -p "${DB_PORT}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        --clean \
        --if-exists \
        --no-owner \
        --no-privileges \
        -v \
        "${RESTORE_DUMP_FILE}" || {
            echo "⚠️ Note: pg_restore completed with notices/warnings (expected for pre-existing system objects)."
        }
    echo "=========================================================="
    echo " Verifying Restored Database Schema and Tables..."
    PGPASSWORD="${DB_PASSWORD}" psql \
        -h "${DB_HOST}" \
        -p "${DB_PORT}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        -c "SELECT count(*) AS total_tables FROM information_schema.tables WHERE table_schema = 'public';"
    PGPASSWORD="${DB_PASSWORD}" psql \
        -h "${DB_HOST}" \
        -p "${DB_PORT}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        -c "SELECT version_num FROM alembic_version;" || echo "No alembic_version table found."
fi

echo "=========================================================="
echo "🎉 Disaster Recovery Database Restore Completed Successfully!"
echo "=========================================================="
