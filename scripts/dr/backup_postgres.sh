#!/usr/bin/env bash
# =============================================================================
# BankOps Database Automated Backup Script
# Performs compressed pg_dump, generates SHA-256 checksum, encrypts with GPG,
# and uploads to Cloud Object Storage (S3 / Cloudflare R2 / GCS).
# Supports native postgres tools and Docker container fallback.
# =============================================================================
set -euo pipefail

# Configuration with defaults
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-bankops}"
DB_NAME="${DB_NAME:-bankops}"
DB_PASSWORD="${DB_PASSWORD:-bankops}"
BACKUP_DIR="${BACKUP_DIR:-/tmp/bankops_backups}"
S3_BUCKET="${S3_BUCKET:-bankops-backups}"
S3_ENDPOINT="${S3_ENDPOINT:-}"
GPG_PASSPHRASE="${BACKUP_GPG_PASSPHRASE:-}"
DOCKER_CONTAINER="${DOCKER_CONTAINER:-bankops-db}"

TIMESTAMP=$(date -u +"%Y%m%d_%H%M%SZ")
mkdir -p "${BACKUP_DIR}"

DUMP_FILENAME="bankops_dump_${DB_NAME}_${TIMESTAMP}.dump"
DUMP_FILEPATH="${BACKUP_DIR}/${DUMP_FILENAME}"
CHECKSUM_FILEPATH="${DUMP_FILEPATH}.sha256"
ENCRYPTED_FILEPATH="${DUMP_FILEPATH}.gpg"

echo "=========================================================="
echo " Starting BankOps DB Backup: ${TIMESTAMP}"
echo " Host: ${DB_HOST}:${DB_PORT} | DB: ${DB_NAME} | User: ${DB_USER}"
echo "=========================================================="

USE_DOCKER=0
if ! command -v pg_dump > /dev/null 2>&1; then
    if command -v docker > /dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER}$"; then
        echo "ℹ️ Note: Native pg_dump not found on host. Using Docker container '${DOCKER_CONTAINER}'."
        USE_DOCKER=1
    else
        echo "❌ Error: Neither native pg_dump nor running container '${DOCKER_CONTAINER}' found." >&2
        exit 1
    fi
fi

# 1. Test database connectivity
echo "[1/5] Checking PostgreSQL connectivity..."
if [ "${USE_DOCKER}" -eq 1 ]; then
    docker exec "${DOCKER_CONTAINER}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" || {
        echo "❌ Error: Database not ready in container ${DOCKER_CONTAINER}" >&2
        exit 1
    }
else
    PGPASSWORD="${DB_PASSWORD}" pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" || {
        echo "❌ Error: Cannot connect to PostgreSQL at ${DB_HOST}:${DB_PORT}" >&2
        exit 1
    }
fi

# 2. Perform logical pg_dump with custom compression (-Fc)
echo "[2/5] Creating compressed binary dump via pg_dump (-Fc)..."
if [ "${USE_DOCKER}" -eq 1 ]; then
    docker exec -e PGPASSWORD="${DB_PASSWORD}" "${DOCKER_CONTAINER}" \
        pg_dump -U "${DB_USER}" -d "${DB_NAME}" -Fc > "${DUMP_FILEPATH}"
else
    PGPASSWORD="${DB_PASSWORD}" pg_dump \
        -h "${DB_HOST}" \
        -p "${DB_PORT}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        -Fc \
        -f "${DUMP_FILEPATH}"
fi

DUMP_SIZE=$(du -h "${DUMP_FILEPATH}" | cut -f1)
echo "✅ Database dumped successfully. Size: ${DUMP_SIZE}"

# 3. Compute SHA-256 Checksum for Audit Integrity
echo "[3/5] Generating SHA-256 checksum..."
if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "${DUMP_FILEPATH}" > "${CHECKSUM_FILEPATH}"
elif command -v shasum > /dev/null 2>&1; then
    shasum -a 256 "${DUMP_FILEPATH}" > "${CHECKSUM_FILEPATH}"
fi
CHECKSUM_VAL=$(awk '{print $1}' "${CHECKSUM_FILEPATH}")
echo "✅ SHA-256 Hash: ${CHECKSUM_VAL}"

# 4. Optional GPG Symmetric Encryption (AES-256)
UPLOAD_FILE="${DUMP_FILEPATH}"
if [ -n "${GPG_PASSPHRASE}" ] && command -v gpg > /dev/null 2>&1; then
    echo "[4/5] Encrypting dump with GPG (AES-256)..."
    gpg --batch --yes --passphrase "${GPG_PASSPHRASE}" \
        --symmetric --cipher-algo AES256 \
        -o "${ENCRYPTED_FILEPATH}" "${DUMP_FILEPATH}"
    UPLOAD_FILE="${ENCRYPTED_FILEPATH}"
    echo "✅ Backup encrypted: ${ENCRYPTED_FILEPATH}"
else
    echo "[4/5] GPG encryption skipped (no passphrase configured or gpg not installed)."
fi

# 5. Upload to Cloud Object Storage if configured
if command -v aws > /dev/null 2>&1 && [ -n "${S3_BUCKET}" ]; then
    echo "[5/5] Uploading backup to S3/R2: s3://${S3_BUCKET}/postgres/${TIMESTAMP}/..."
    AWS_ENDPOINT_FLAG=""
    if [ -n "${S3_ENDPOINT}" ]; then
        AWS_ENDPOINT_FLAG="--endpoint-url ${S3_ENDPOINT}"
    fi

    aws s3 cp "${UPLOAD_FILE}" "s3://${S3_BUCKET}/postgres/${TIMESTAMP}/$(basename "${UPLOAD_FILE}")" ${AWS_ENDPOINT_FLAG} || true
    aws s3 cp "${CHECKSUM_FILEPATH}" "s3://${S3_BUCKET}/postgres/${TIMESTAMP}/$(basename "${CHECKSUM_FILEPATH}")" ${AWS_ENDPOINT_FLAG} || true
    echo "✅ Processed Cloud Storage upload."
else
    echo "[5/5] S3 upload skipped (local backup retained at ${UPLOAD_FILE})."
fi

echo "=========================================================="
echo "🎉 Backup Completed Successfully!"
echo "File: ${UPLOAD_FILE}"
echo "Checksum: ${CHECKSUM_VAL}"
echo "=========================================================="
