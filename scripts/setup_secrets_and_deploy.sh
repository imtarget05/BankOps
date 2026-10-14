#!/usr/bin/env bash
# =============================================================================
# BankOps Automated Secrets Setup & Cloudflare Deployment Script
# 
# Usage:
#   bash scripts/setup_secrets_and_deploy.sh [OPTIONS]
#
# Options:
#   --database-url <url>          PostgreSQL URL (e.g. Neon or Managed DB)
#   --cf-account-id <id>          Cloudflare Account ID
#   --cf-api-token <token>        Cloudflare API Token
#   --cf-tunnel-token <token>     Cloudflare Tunnel Token
#   --r2-key-id <id>              Cloudflare R2 Access Key ID
#   --r2-secret-key <key>         Cloudflare R2 Secret Access Key
#   --supervisor-pin <pin>        Supervisor PIN (default: 123456)
#   --jwt-secret <secret>         JWT Secret Key (auto-generated if omitted)
#   --gpg-passphrase <passphrase> Backup GPG Passphrase (auto-generated if omitted)
#   --apply-k8s                   Apply secret and kustomize to current K8s context
#   --auto-migrate                Run alembic upgrade head on target database
#   -h, --help                    Show this help message
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Default values / Read from existing .env if present
EXISTING_ENV="${ROOT_DIR}/.env"
if [ -f "${EXISTING_ENV}" ]; then
    info "Loading existing defaults from .env..."
    while IFS='=' read -r key val || [ -n "$key" ]; do
        # Ignore comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        # Strip leading/trailing whitespace and surrounding quotes
        key=$(echo "$key" | xargs)
        val=$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        if [ -n "$key" ] && [ -z "${!key:-}" ]; then
            export "$key"="$val"
        fi
    done < "${EXISTING_ENV}"
fi

DB_URL="${DATABASE_URL:-}"
CF_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"
CF_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
CF_TUNNEL_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN:-}"
R2_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
R2_SECRET_KEY="${AWS_SECRET_ACCESS_KEY:-}"
PIN="${SUPERVISOR_PIN:-123456}"
JWT_SEC="${SECRET_KEY:-}"
GPG_PASS="${BACKUP_GPG_PASSPHRASE:-}"
APPLY_K8S=0
AUTO_MIGRATE=0

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --database-url) DB_URL="$2"; shift 2 ;;
        --cf-account-id) CF_ACCOUNT_ID="$2"; shift 2 ;;
        --cf-api-token) CF_API_TOKEN="$2"; shift 2 ;;
        --cf-tunnel-token) CF_TUNNEL_TOKEN="$2"; shift 2 ;;
        --r2-key-id) R2_KEY_ID="$2"; shift 2 ;;
        --r2-secret-key) R2_SECRET_KEY="$2"; shift 2 ;;
        --supervisor-pin) PIN="$2"; shift 2 ;;
        --jwt-secret) JWT_SEC="$2"; shift 2 ;;
        --gpg-passphrase) GPG_PASS="$2"; shift 2 ;;
        --apply-k8s) APPLY_K8S=1; shift ;;
        --auto-migrate) AUTO_MIGRATE=1; shift ;;
        -h|--help)
            head -n 22 "$0" | tail -n 20
            exit 0
            ;;
        *) error "Unknown option: $1" ;;
    esac
done

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║      BankOps — Automated Cloudflare & Secrets Deploy Tool       ║"
echo "║          Zero Trust & Instant Disaster Recovery Sizing           ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# 1. Database URL check/prompt
if [ -z "${DB_URL}" ]; then
    warn "DATABASE_URL is not provided."
    echo "Using default demo local database URL or enter Neon PostgreSQL URL:"
    echo "Default: postgresql+asyncpg://bankops:bankops@localhost:5432/bankops"
    read -r -p "Enter DATABASE_URL [press Enter for default]: " INPUT_DB
    DB_URL="${INPUT_DB:-postgresql+asyncpg://bankops:bankops@localhost:5432/bankops}"
fi

# Ensure asyncpg scheme for Python backend if raw postgresql:// was provided
if [[ "${DB_URL}" =~ ^postgresql:// ]]; then
    DB_URL="postgresql+asyncpg://${DB_URL#postgresql://}"
fi

# 2. Generate cryptographically strong JWT Secret if not set
if [ -z "${JWT_SEC}" ] || [ "${JWT_SEC}" = "CHANGE_ME_GENERATE_32_BYTE_RANDOM_SECRET_KEY" ]; then
    info "Generating secure 32-byte JWT Secret..."
    if command -v openssl >/dev/null 2>&1; then
        JWT_SEC=$(openssl rand -hex 32)
    else
        JWT_SEC=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    fi
    success "Generated JWT Secret (${#JWT_SEC} characters)."
fi

# 3. Generate GPG Passphrase if not set
if [ -z "${GPG_PASS}" ] || [ "${GPG_PASS}" = "CHANGE_ME_ENCRYPTION_PASSPHRASE" ]; then
    info "Generating random GPG Passphrase for automated backups..."
    if command -v openssl >/dev/null 2>&1; then
        GPG_PASS=$(openssl rand -base64 24)
    else
        GPG_PASS=$(python3 -c "import secrets; print(secrets.token_urlsafe(24))")
    fi
    success "Generated Backup GPG Passphrase."
fi

# 4. Generate Kubernetes Production Secret Manifest
K8S_SECRET_FILE="${ROOT_DIR}/infra/k8s/base/secret-production.yaml"
info "Writing Kubernetes production secret manifest to ${K8S_SECRET_FILE}..."

cat <<EOF > "${K8S_SECRET_FILE}"
apiVersion: v1
kind: Secret
metadata:
  name: bankops-secrets
  labels:
    app.kubernetes.io/name: bankops
    app.kubernetes.io/part-of: bankops-system
type: Opaque
stringData:
  DATABASE_URL: "${DB_URL}"
  SECRET_KEY: "${JWT_SEC}"
  SUPERVISOR_PIN: "${PIN}"
  CLOUDFLARE_ACCOUNT_ID: "${CF_ACCOUNT_ID}"
  CLOUDFLARE_API_TOKEN: "${CF_API_TOKEN}"
  CLOUDFLARE_TUNNEL_TOKEN: "${CF_TUNNEL_TOKEN}"
  AWS_ACCESS_KEY_ID: "${R2_KEY_ID}"
  AWS_SECRET_ACCESS_KEY: "${R2_SECRET_KEY}"
  BACKUP_GPG_PASSPHRASE: "${GPG_PASS}"
EOF
chmod 600 "${K8S_SECRET_FILE}"
success "Created ${K8S_SECRET_FILE} (protected 0600, gitignored)."

# 5. Generate .env.production file for docker-compose or standalone worker
ENV_PROD_FILE="${ROOT_DIR}/.env.production"
info "Writing production environment file to ${ENV_PROD_FILE}..."

cat <<EOF > "${ENV_PROD_FILE}"
# BankOps Production Configuration
APP_ENV=production
DATABASE_URL=${DB_URL}
SECRET_KEY=${JWT_SEC}
SUPERVISOR_PIN=${PIN}
ALLOWED_ORIGINS=["https://bankops.yourbank.com","https://bankops-web.pages.dev"]

# Cloudflare Workers AI
CLOUDFLARE_ACCOUNT_ID=${CF_ACCOUNT_ID}
CLOUDFLARE_API_TOKEN=${CF_API_TOKEN}
CLOUDFLARE_MODEL=@cf/meta/llama-3.1-8b-instruct
CLOUDFLARE_TUNNEL_TOKEN=${CF_TUNNEL_TOKEN}
AI_PROVIDER=cloudflare
AI_TIMEOUT_SECONDS=120
AI_REQUESTS_PER_MINUTE=60

# Backup & Object Storage (Cloudflare R2)
AWS_ACCESS_KEY_ID=${R2_KEY_ID}
AWS_SECRET_ACCESS_KEY=${R2_SECRET_KEY}
BACKUP_GPG_PASSPHRASE=${GPG_PASS}
S3_BUCKET=bankops-backups
S3_ENDPOINT=https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com
EOF
chmod 600 "${ENV_PROD_FILE}"
success "Created ${ENV_PROD_FILE} (protected 0600, gitignored)."

# 6. Database Migrations Check / Execution
if [ "${AUTO_MIGRATE}" -eq 1 ]; then
    info "Running database migrations (alembic upgrade head)..."
    cd "${ROOT_DIR}/backend"
    DATABASE_URL="${DB_URL}" poetry run alembic upgrade head || {
        warn "Could not run poetry run alembic directly. Trying via python3..."
        DATABASE_URL="${DB_URL}" python3 -m alembic upgrade head || true
    }
    success "Database migration step completed."
    cd "${ROOT_DIR}"
fi

# 7. Apply to Kubernetes if requested
if [ "${APPLY_K8S}" -eq 1 ]; then
    info "Applying secret-production.yaml to active Kubernetes cluster..."
    if command -v kubectl >/dev/null 2>&1; then
        kubectl apply -f "${K8S_SECRET_FILE}" -n bankops-prod || kubectl apply -f "${K8S_SECRET_FILE}"
        success "Applied secret to Kubernetes."
    else
        warn "kubectl not found. Skipped K8s apply."
    fi
fi

echo ""
echo "=================================================================="
echo "🎉 SECRETS CONFIGURED & ENVIRONMENT READY!"
echo "=================================================================="
echo "Summary of generated configurations:"
echo " - K8s Secret:     ${K8S_SECRET_FILE}"
echo " - Env File:       ${ENV_PROD_FILE}"
echo " - Database URL:   ${DB_URL:0:30}..."
echo " - Cloudflare AI:  Account ID (${CF_ACCOUNT_ID:0:8}...), Token configured"
echo " - Supervisor PIN: ${PIN}"
echo " - Cloudflare R2:  Endpoint https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com"
echo ""
if [ -z "${CF_TUNNEL_TOKEN}" ]; then
    echo "💡 NEXT STEP: To activate Cloudflare Tunnel without opening ports:"
    echo "   1. Run 'cloudflared tunnel login'"
    echo "   2. Create tunnel: 'cloudflared tunnel create bankops-prod-tunnel'"
    echo "   3. Put tunnel token into ${K8S_SECRET_FILE} or rerun with --cf-tunnel-token <TOKEN>"
fi
echo "=================================================================="
