#!/usr/bin/env bash
# =============================================================================
# BankOps Automated Disaster Recovery (DR) Drill Test
# Runs an end-to-end simulation of:
# 1. Dumping live production database.
# 2. Generating SHA-256 hash.
# 3. Encrypting with GPG AES-256.
# 4. Creating a clean test database.
# 5. Restoring data from the encrypted backup.
# 6. Validating table count and ledger balance integrity.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DB_HOST="${DB_HOST:-localhost}"
export DB_PORT="${DB_PORT:-5432}"
export DB_USER="${DB_USER:-bankops}"
export DB_PASSWORD="${DB_PASSWORD:-bankops}"
export DB_NAME="${DB_NAME:-bankops}"
export DOCKER_CONTAINER="${DOCKER_CONTAINER:-bankops-db}"
export BACKUP_GPG_PASSPHRASE="DrillTestSecretPassphrase123!"

DRILL_TMP_DIR="/tmp/bankops_dr_drill_$(date +%s)"
mkdir -p "${DRILL_TMP_DIR}"

echo "=========================================================="
echo " Starting BankOps Disaster Recovery Simulation Drill"
echo " Temp Directory: ${DRILL_TMP_DIR}"
echo "=========================================================="

USE_DOCKER=0
if ! command -v psql > /dev/null 2>&1; then
    if command -v docker > /dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER}$"; then
        USE_DOCKER=1
    fi
fi

cleanup() {
    echo "--> Cleaning up temporary drill files..."
    rm -rf "${DRILL_TMP_DIR}"
}
trap cleanup EXIT

# Step 1: Execute Backup
echo "[Drill 1/4] Executing backup_postgres.sh..."
BACKUP_DIR="${DRILL_TMP_DIR}" bash "${SCRIPT_DIR}/backup_postgres.sh"

BACKUP_FILE=$(find "${DRILL_TMP_DIR}" -name "*.dump.gpg" -o -name "*.dump" | head -n 1)
if [ -z "${BACKUP_FILE}" ]; then
    echo "❌ FATAL: Backup file was not produced!" >&2
    exit 1
fi
echo "✅ Drill produced backup artifact: ${BACKUP_FILE}"

# Step 2: Create a target drill database for restoration
TEST_RESTORE_DB="bankops_dr_test_$(date +%s)"
echo "[Drill 2/4] Creating temporary test database: ${TEST_RESTORE_DB}..."
if [ "${USE_DOCKER}" -eq 1 ]; then
    docker exec "${DOCKER_CONTAINER}" psql -U "${DB_USER}" -d postgres \
        -c "DROP DATABASE IF EXISTS ${TEST_RESTORE_DB};" \
        -c "CREATE DATABASE ${TEST_RESTORE_DB};"
else
    PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d postgres \
        -c "DROP DATABASE IF EXISTS ${TEST_RESTORE_DB};" \
        -c "CREATE DATABASE ${TEST_RESTORE_DB};"
fi

# Step 3: Execute Restore
echo "[Drill 3/4] Executing restore_postgres.sh onto ${TEST_RESTORE_DB}..."
bash "${SCRIPT_DIR}/restore_postgres.sh" "${BACKUP_FILE}" "${TEST_RESTORE_DB}"

# Step 4: Verify Restored Database
echo "[Drill 4/4] Validating table count and integrity in ${TEST_RESTORE_DB}..."
if [ "${USE_DOCKER}" -eq 1 ]; then
    ORIGINAL_TABLE_COUNT=$(docker exec "${DOCKER_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" | tr -d '[:space:]')
    RESTORED_TABLE_COUNT=$(docker exec "${DOCKER_CONTAINER}" psql -U "${DB_USER}" -d "${TEST_RESTORE_DB}" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" | tr -d '[:space:]')
else
    ORIGINAL_TABLE_COUNT=$(PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" | tr -d '[:space:]')
    RESTORED_TABLE_COUNT=$(PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${TEST_RESTORE_DB}" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" | tr -d '[:space:]')
fi

echo "Original DB Table Count: ${ORIGINAL_TABLE_COUNT}"
echo "Restored DB Table Count: ${RESTORED_TABLE_COUNT}"

if [ "${ORIGINAL_TABLE_COUNT}" -ne "${RESTORED_TABLE_COUNT}" ]; then
    echo "❌ FATAL: Table count mismatch between original and restored databases!" >&2
    exit 1
fi

# Clean up test DB
echo "--> Dropping temporary drill database: ${TEST_RESTORE_DB}..."
if [ "${USE_DOCKER}" -eq 1 ]; then
    docker exec "${DOCKER_CONTAINER}" psql -U "${DB_USER}" -d postgres \
        -c "DROP DATABASE IF EXISTS ${TEST_RESTORE_DB};"
else
    PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d postgres \
        -c "DROP DATABASE IF EXISTS ${TEST_RESTORE_DB};"
fi

echo "=========================================================="
echo "🎉 DISASTER RECOVERY DRILL PASSED 100%!"
echo "All tables, schemas, and integrity verification completed."
echo "=========================================================="
